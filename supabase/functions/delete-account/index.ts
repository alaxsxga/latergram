// =====================================================================
// delete-account Edge Function
//
// 用途：永久刪除當前登入使用者的帳號與所有資料（Apple Guideline 5.1.1(v)）。
//   - 驗證 JWT 取出 user id
//   - 若使用者是用 Sign in with Apple 登入 → 先呼叫 Apple 撤銷授權（見下）
//   - service_role 呼叫 auth.admin.deleteUser(userId)
//   - 刪除 auth.users 一列後，靠 DB 外鍵 cascade 連帶清掉該用戶散在各表的資料：
//       profiles / friendships / messages / invite_tokens(inviter_id)
//       / message_deletions / processed_transactions / feedback
//     invite_tokens.invitee_id 走 ON DELETE SET NULL（別人的 token 保留、只清該格）
//     → 見 migration 20260701120000_invitee_id_set_null_on_delete.sql
//
// Apple token revoke（5.1.1(v) 硬性要求，Apple 用戶刪帳號時必須撤銷授權）：
//   - client 在刪帳號當下重新做一次 Sign in with Apple，取得新的 authorizationCode，
//     隨 body { appleAuthorizationCode } 送來（native signInWithIdToken 不會留 refresh token，
//     所以只能當下重新換一組來 revoke）。
//   - 本函式用 .p8 私鑰簽 client_secret（ES256 JWT）→ code 換 refresh_token → 打 /auth/revoke。
//   - revoke 失敗一律「擋下刪除」回錯誤，讓 client 重試（避免留下未撤銷的 Apple 授權）。
//
// 安全性：
//   - 只能刪「自己」——userId 取自 gateway 已驗過簽章的 JWT，client 無法指定他人
//   - service_role bypass RLS，是刪 auth.users 的唯一途徑（client 端做不到）
//   - Apple 用戶（JWT app_metadata.provider == apple）強制要求帶 code，缺就擋下（400）
//
// 環境變數（Supabase 自動注入 + Dashboard → Edge Functions → Secrets 手動設定）：
//   - SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY   ← 自動注入
//   - APPLE_TEAM_ID     ← Apple Developer Team ID（10 碼）
//   - APPLE_KEY_ID      ← Sign in with Apple 金鑰的 Key ID
//   - APPLE_PRIVATE_KEY ← 該金鑰 .p8 內容（含 BEGIN/END 行；\n 會自動還原）
//   - APPLE_CLIENT_ID   ← 選填，預設 BUNDLE_ID（native app 的 client_id = bundle id）
// =====================================================================

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import * as jose from "npm:jose@5.9.6";

const BUNDLE_ID = "com.ininder.ed.latergram";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function b64UrlDecode(s: string): string {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  return atob(padded);
}

// Apple 撤銷授權：code → refresh_token → /auth/revoke。任一步失敗即 throw（呼叫端擋下刪除）。
async function revokeAppleAuthorization(authorizationCode: string): Promise<void> {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const privateKeyPem = Deno.env.get("APPLE_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  const clientId = Deno.env.get("APPLE_CLIENT_ID") ?? BUNDLE_ID;
  if (!teamId || !keyId || !privateKeyPem) {
    throw new Error("apple revoke secrets not configured");
  }

  // client_secret：ES256 JWT，用 .p8 私鑰簽（有效期短，一次性）
  const privateKey = await jose.importPKCS8(privateKeyPem, "ES256");
  const clientSecret = await new jose.SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt()
    .setExpirationTime("5m")
    .setAudience("https://appleid.apple.com")
    .setSubject(clientId)
    .sign(privateKey);

  // 1) authorizationCode → refresh_token
  const tokenResp = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: "authorization_code",
      code: authorizationCode,
    }),
  });
  if (!tokenResp.ok) {
    throw new Error(`token exchange failed: ${tokenResp.status} ${await tokenResp.text()}`);
  }
  const tokenJson = await tokenResp.json() as { refresh_token?: string; access_token?: string };
  const token = tokenJson.refresh_token ?? tokenJson.access_token;
  const tokenTypeHint = tokenJson.refresh_token ? "refresh_token" : "access_token";
  if (!token) throw new Error("token response missing refresh/access token");

  // 2) revoke
  const revokeResp = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      token,
      token_type_hint: tokenTypeHint,
    }),
  });
  if (!revokeResp.ok) {
    throw new Error(`revoke failed: ${revokeResp.status} ${await revokeResp.text()}`);
  }
}

serve(async (req: Request) => {
  if (req.method !== "POST") return jsonError("method not allowed", 405);

  // 取出 user id：gateway 已驗過 JWT 簽章（verify_jwt 預設 true），
  // 這裡只 decode payload 拿 sub（避開 supabase-js 對 ES256 asymmetric JWT 的相容性問題）
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    console.error("missing authorization header");
    return jsonError("missing auth", 401);
  }

  let userId: string;
  let payload: Record<string, unknown>;
  try {
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    const parts = token.split(".");
    if (parts.length !== 3) throw new Error("invalid jwt format");
    payload = JSON.parse(b64UrlDecode(parts[1])) as Record<string, unknown>;
    if (typeof payload.sub !== "string") throw new Error("jwt missing sub");
    if (typeof payload.exp === "number" && payload.exp * 1000 < Date.now()) {
      throw new Error("jwt expired");
    }
    userId = payload.sub;
  } catch (e) {
    console.error("JWT decode failed:", e);
    return jsonError("invalid session", 401);
  }

  // 解析 body（可能夾帶 Apple authorizationCode）；沒有 body 也允許（純 email 用戶）
  let appleAuthorizationCode: string | undefined;
  try {
    const body = await req.json();
    if (body && typeof body.appleAuthorizationCode === "string" && body.appleAuthorizationCode.length > 0) {
      appleAuthorizationCode = body.appleAuthorizationCode;
    }
  } catch {
    // 無 body / 非 JSON：視為 email 用戶
  }

  // Apple 用戶必須撤銷授權才允許刪除
  const appMeta = payload.app_metadata as { provider?: string; providers?: string[] } | undefined;
  const isApple = appMeta?.provider === "apple" || (appMeta?.providers?.includes("apple") ?? false);
  if (isApple) {
    if (!appleAuthorizationCode) {
      console.error("apple user missing authorization code");
      return jsonError("apple authorization code required", 400);
    }
    try {
      await revokeAppleAuthorization(appleAuthorizationCode);
      console.log("apple authorization revoked:", userId);
    } catch (e) {
      // 撤銷失敗 → 擋下刪除，讓 client 重試（不留下未撤銷授權）
      console.error("apple revoke failed:", e);
      return jsonError("apple revoke failed", 502);
    }
  }

  // 刪除 auth 使用者 → 連帶 cascade 清掉所有關聯資料
  const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);
  if (error) {
    console.error("deleteUser failed:", error);
    return jsonError("delete failed", 500);
  }

  console.log("account deleted:", userId);
  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
