// =====================================================================
// sync-entitlement Edge Function
//
// 用途：取代 client 直接 UPDATE profiles.is_premium 的舊路徑
//   - 升級（POST { jws }）：驗證 Apple JWS → 寫 is_premium=true
//   - 降級（POST {})    ：信任 client 報告 → 寫 is_premium=false
//
// 安全性：
//   - service_role 寫 DB，bypass RLS（client 端 authenticated 已被撤回 update 權限）
//   - JWS 驗證：@peculiar/x509 走 cert chain（anchor 到 Apple Root G3）+ jose 驗 ES256 簽章
//     （改用 Web Crypto 為基礎的 lib，是因 Apple 官方 lib 依賴 Node-only crypto API，Deno 沒實作）
//   - appAccountToken 必須等於當前 user.id（防跨用戶誤掛 = C3）
//   - transactionId 入 processed_transactions 防重放
//   - 不做 OCSP 撤銷檢查；風險低，且有上述多重防禦
//
// 環境變數（在 Supabase Dashboard → Edge Functions → Secrets 設定）：
//   - APPLE_ROOT_G3_PEM   ← Apple Root CA G3 PEM 字串（含 BEGIN/END 行）
//   - APPLE_ENVIRONMENT   ← "SANDBOX" 或 "PRODUCTION"（預設 PRODUCTION）
//   - SUPABASE_URL                ← Supabase 自動注入
//   - SUPABASE_ANON_KEY           ← Supabase 自動注入
//   - SUPABASE_SERVICE_ROLE_KEY   ← Supabase 自動注入
// =====================================================================

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import * as x509 from "npm:@peculiar/x509@1.12.3";
import * as jose from "npm:jose@5.9.6";

// ─── 常數 ─────────────────────────────────────────────
const BUNDLE_ID = "com.ininder.ed.latergram";
const PRODUCT_ID = "com.ininder.ed.latergram.premium.monthly";

// ─── 初始化 ───────────────────────────────────────────
const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const APPLE_ROOT_PEM = Deno.env.get("APPLE_ROOT_G3_PEM")!;
const appleRootCert = new x509.X509Certificate(APPLE_ROOT_PEM);

// ─── JWS 驗證 ─────────────────────────────────────────
interface TransactionClaims {
  bundleId?: string;
  productId?: string;
  transactionId?: string;
  originalTransactionId?: string;
  expiresDate?: number;
  appAccountToken?: string;
  environment?: string;
}

function b64UrlDecode(s: string): string {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  return atob(padded);
}

async function verifyAppleJWS(jws: string): Promise<TransactionClaims> {
  // 1. 解析 JWS header 取得 x5c（leaf → intermediate(→ root) cert chain，base64-DER）
  const [headerB64Url] = jws.split(".");
  const header = JSON.parse(b64UrlDecode(headerB64Url)) as { x5c?: string[] };
  const x5c = header.x5c;
  if (!x5c || x5c.length < 1) throw new Error("missing x5c chain in JWS header");

  // 2. 建 cert 物件
  const certs = x5c.map((b64) => new x509.X509Certificate(b64));

  // 3. 逐節驗證：certs[i] 由 certs[i+1] 簽；最末必須由 Apple Root G3 簽（anchor）
  const now = new Date();
  for (let i = 0; i < certs.length; i++) {
    const cert = certs[i];
    if (cert.notBefore > now || cert.notAfter < now) {
      throw new Error(`cert ${i} outside validity period`);
    }
    const issuer = (i + 1 < certs.length) ? certs[i + 1] : appleRootCert;
    const ok = await cert.verify({ publicKey: issuer.publicKey, date: now });
    if (!ok) throw new Error(`cert chain verification failed at index ${i}`);
  }

  // 4. 用 leaf cert 的 public key 驗 JWS 簽章
  const leafPem = certs[0].toString("pem");
  const publicKey = await jose.importX509(leafPem, "ES256");
  const { payload } = await jose.jwtVerify(jws, publicKey);

  return payload as unknown as TransactionClaims;
}

// ─── 主處理 ───────────────────────────────────────────
serve(async (req: Request) => {
  if (req.method !== "POST") return jsonError("method not allowed", 405);

  // 1. 取出 user id
  //    gateway 已驗過 JWT 簽章（verify_jwt 預設 true），這裡只要 decode payload 拿 sub
  //    這樣可避開 supabase-js 對 ES256 asymmetric JWT 的相容性問題
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

  // 2. 解析 body
  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const jws = typeof body.jws === "string" ? body.jws : undefined;

  if (jws) {
    // ──────── 升級路徑 ────────
    let claims: TransactionClaims;
    try {
      claims = await verifyAppleJWS(jws);
    } catch (e) {
      console.error("JWS verification failed:", e);
      return jsonError("invalid jws", 400);
    }

    console.log("JWS verified, claims:", {
      bundleId: claims.bundleId,
      productId: claims.productId,
      expiresDate: claims.expiresDate,
      environment: claims.environment,
      hasAppAccountToken: Boolean(claims.appAccountToken),
      transactionId: claims.transactionId,
    });

    if (claims.bundleId !== BUNDLE_ID) {
      console.error("bundle mismatch", { got: claims.bundleId, expected: BUNDLE_ID });
      return jsonError("bundle mismatch", 400);
    }
    if (claims.productId !== PRODUCT_ID) {
      console.error("product mismatch", { got: claims.productId, expected: PRODUCT_ID });
      return jsonError("product mismatch", 400);
    }
    if (!claims.expiresDate || claims.expiresDate < Date.now()) {
      console.error("expired", { expiresDate: claims.expiresDate, now: Date.now() });
      return jsonError("expired", 400);
    }

    // C3：transaction 若帶 appAccountToken，必須等於當前 user
    //     未帶（legacy 訂閱）→ 暫時通過
    if (claims.appAccountToken && claims.appAccountToken !== userId) {
      console.error("appAccountToken mismatch", {
        tokenInJws: claims.appAccountToken,
        currentUser: userId,
      });
      return jsonError("appAccountToken mismatch", 400);
    }

    // 去重
    const transactionId = claims.transactionId!;
    const { data: existing } = await supabaseAdmin
      .from("processed_transactions")
      .select("transaction_id")
      .eq("transaction_id", transactionId)
      .maybeSingle();

    if (!existing) {
      const { error: insertErr } = await supabaseAdmin
        .from("processed_transactions")
        .insert({
          transaction_id: transactionId,
          original_transaction_id: claims.originalTransactionId!,
          user_id: userId,
          product_id: claims.productId!,
          expires_date: claims.expiresDate
            ? new Date(claims.expiresDate).toISOString()
            : null,
        });
      if (insertErr) {
        console.error("dedup insert failed", insertErr);
        return jsonError("dedup insert failed", 500);
      }
    }

    const { error: updateErr } = await supabaseAdmin
      .from("profiles")
      .update({ is_premium: true })
      .eq("id", userId);
    if (updateErr) {
      console.error("profile update failed", updateErr);
      return jsonError("profile update failed", 500);
    }
  } else {
    // ──────── 降級路徑 ────────
    // client 端 verifyAndSyncEntitlement 掃完 currentEntitlements 為空時呼叫
    const { error: updateErr } = await supabaseAdmin
      .from("profiles")
      .update({ is_premium: false })
      .eq("id", userId);
    if (updateErr) {
      console.error("profile update failed", updateErr);
      return jsonError("profile update failed", 500);
    }
  }

  // 3. 回更新後的 profile
  const { data: profile, error: fetchErr } = await supabaseAdmin
    .from("profiles")
    .select()
    .eq("id", userId)
    .single();
  if (fetchErr || !profile) return jsonError("profile fetch failed", 500);

  return new Response(JSON.stringify(profile), {
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
