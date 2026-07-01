// =====================================================================
// delete-account Edge Function
//
// 用途：永久刪除當前登入使用者的帳號與所有資料（Apple Guideline 5.1.1(v)）。
//   - 驗證 JWT 取出 user id
//   - service_role 呼叫 auth.admin.deleteUser(userId)
//   - 刪除 auth.users 一列後，靠 DB 外鍵 cascade 連帶清掉該用戶散在各表的資料：
//       profiles / friendships / messages / invite_tokens(inviter_id)
//       / message_deletions / processed_transactions / feedback
//     invite_tokens.invitee_id 走 ON DELETE SET NULL（別人的 token 保留、只清該格）
//     → 見 migration 20260701120000_invitee_id_set_null_on_delete.sql
//
// 安全性：
//   - 只能刪「自己」——userId 取自 gateway 已驗過簽章的 JWT，client 無法指定他人
//   - service_role bypass RLS，是刪 auth.users 的唯一途徑（client 端做不到）
//
// 環境變數（Supabase 自動注入）：
//   - SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
// =====================================================================

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function b64UrlDecode(s: string): string {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  return atob(padded);
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
  try {
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    const parts = token.split(".");
    if (parts.length !== 3) throw new Error("invalid jwt format");
    const payload = JSON.parse(b64UrlDecode(parts[1])) as Record<string, unknown>;
    if (typeof payload.sub !== "string") throw new Error("jwt missing sub");
    if (typeof payload.exp === "number" && payload.exp * 1000 < Date.now()) {
      throw new Error("jwt expired");
    }
    userId = payload.sub;
  } catch (e) {
    console.error("JWT decode failed:", e);
    return jsonError("invalid session", 401);
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
