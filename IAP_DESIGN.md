# IAP 與 Manual Premium 完整設計

> 最後更新：2026-06-02
> 相關檔案：
> - App：`Sources/LatergramPrototype/Dependencies/PurchaseClient.swift`、`Sources/LatergramPrototype/App/AppFeature.swift`、`Sources/LatergramPrototype/Features/Paywall/PaywallFeature.swift`、`Sources/LatergramPrototype/Dependencies/CurrentUserClient.swift`
> - Supabase：`supabase/functions/sync-entitlement/index.ts`、`supabase/migrations/20260528120000_c1_entitlement_guard.sql`、`supabase/migrations/20260602120000_manual_premium_grant.sql`

---

## 目錄

1. [設計目標](#1-設計目標)
2. [資料模型](#2-資料模型)
3. [系統角色分工](#3-系統角色分工)
4. [核心流程](#4-核心流程)
5. [安全防禦（C1 / C3 / 去重 / Self-heal）](#5-安全防禦)
6. [UI 進入點](#6-ui-進入點)
7. [設計重點與為什麼](#7-設計重點與為什麼)
8. [Cases 全排列組合](#8-cases-全排列組合)
9. [Edge Cases 清單](#9-edge-cases-清單)

---

## 1. 設計目標

- **真實付費為準**：以 Apple StoreKit 2 的 `Transaction.currentEntitlements` 為唯一 IAP 真實狀態，DB 上的 `is_premium` 是它的鏡像。
- **防偽**：client 不可直接 `UPDATE profiles SET is_premium=true`。所有 entitlement 寫入都必須經過 Edge Function 並通過 Apple JWS cert chain 驗證。
- **防跨用戶誤掛**：transaction 必須帶 `appAccountToken == auth.uid()`（C3），否則不採信。
- **可手動補償**：客服 / 白名單 / KOL 補贈，可繞過 IAP 給 premium，但與 IAP 來源**互斥可辨識**（`premium_source`）。
- **不依賴 server-side scheduler**：不開 pg_cron，過期 manual 在用戶下次開 App 時由 Edge Function self-heal。
- **失敗可重試**：sync 失敗時 Apple transaction 留 unfinished，下次 `verifyAndSyncEntitlement` 從 `currentEntitlements` 撿回；server 端 `processed_transactions` 同 transaction id 不會重寫。

---

## 2. 資料模型

### 2.1 `public.profiles`（entitlement 主體）

| 欄位 | 型別 | 寫入者 | 用途 |
|---|---|---|---|
| `id` | `uuid` | (auth) | = `auth.users.id` |
| `is_premium` | `bool` | service_role / trigger | 主開關，UI 唯一判斷依據 |
| `message_limit` | `int` | trigger（不可手動寫） | premium=3 / free=1，由 `sync_premium_entitlements` 推導 |
| `max_delay_seconds` | `int` | service_role | free=86400（1 天），premium=無上限（未來再決定上限） |
| `premium_source` | `text` ∈ {`iap`, `manual`, `null`} | service_role | entitlement 來源；free 用戶為 `null` |
| `premium_until` | `timestamptz` | service_role | 到期日；`null` = 無限期（IAP 中極少數 legacy 或 manual 永久白名單） |
| `display_name` | `text` | authenticated（白名單） | 唯一允許 client UPDATE 的 entitlement 鄰近欄位 |

**Trigger `profiles_sync_entitlements`**（C1 migration）：
- BEFORE UPDATE OF `is_premium`：若 `is_premium` 變動，自動同步 `message_limit`（true→3、false→1）。
- 未來要加新 entitlement（例如 `voice_message_quota`）只動 SQL function，不必發版。

### 2.2 `public.processed_transactions`（去重 / 對帳稽核）

| 欄位 | 型別 | 用途 |
|---|---|---|
| `transaction_id` | `text PK` | Apple 的本筆 transactionId，去重關鍵 |
| `original_transaction_id` | `text` | 訂閱原始 transactionId，跨續期查同訂閱 |
| `user_id` | `uuid FK profiles(id)` | 寫入時的當前 user |
| `product_id` | `text` | 目前固定 `com.ininder.ed.latergram.premium.monthly` |
| `expires_date` | `timestamptz` | 來自 JWS claims，可 null（legacy） |
| `processed_at` | `timestamptz` | 寫入時間，對帳用 |

- RLS：完全不對 authenticated 開放（沒建 policy）。只有 service_role 可讀寫。
- 用途：防 JWS 重放、客服查帳、未來退款對帳。

### 2.3 Client 端鏡像

`Sources/LatergramPrototype/Dependencies/CurrentUserClient.swift`：
- `CurrentUserStore.shared`：in-memory 單一 source of truth，所有 UI 透過 `currentUserClient.isPremium()` / `messageLimit()` / `maxDelaySeconds()` 讀取。
- 任何更新 entitlement 的路徑（登入、purchase 成功、Transaction.updates、scenePhase active、profileRefreshed）都會呼叫 `currentUserClient.update(profile)`。
- **不持久化到 disk**：登出後重置為空 profile（CLAUDE.md 規則 1：logout 必須 clean slate）。

---

## 3. 系統角色分工

```
┌──────────────────┐          ┌─────────────────────┐          ┌────────────────┐
│   App (client)   │          │  Supabase           │          │   Apple        │
│                  │          │                     │          │                │
│  PurchaseClient  │──jws──▶  │  Edge Function      │          │  StoreKit 2    │
│  CurrentUserClnt │          │  sync-entitlement   │          │  App Store     │
│  AppFeature      │◀─profile─│                     │          │                │
│  PaywallFeature  │          │  ↓ service_role     │          │  JWS (ES256)   │
│                  │          │  ↓ bypass RLS       │ ─chain──▶│  Apple Root G3 │
└──────────────────┘          │  profiles 表        │          └────────────────┘
                              │  processed_trans... │
                              │                     │
                              │  Trigger 推導       │
                              │  message_limit      │
                              └─────────────────────┘
                                       ▲
                                       │ service_role / SQL Editor
                              ┌────────┴────────┐
                              │  人工：客服 / KOL │
                              │  下白名單 SQL    │
                              └─────────────────┘
```

### 3.1 App 端負責

| 責任 | 程式碼位置 | 備註 |
|---|---|---|
| 取 products（價格、locale）| `PurchaseClient.fetchProducts` | StoreKit `Product.products(for:)` |
| 觸發購買並帶 `appAccountToken=auth.uid()` | `PurchaseClient.purchase` | C3 防跨用戶誤掛 |
| 將 JWS 上傳給 Edge Function | `syncPremium(jws:)` | 一條 path，升級 / 降級共用 |
| **不直接 UPDATE profiles**（C1 已撤回權限）| — | 沒得選；強撤 SQL 也會被 RLS 擋 |
| 訂閱**自然到期**主動 demote | `verifyAndSyncEntitlement`（POST 空 body）| Apple 不會推 update event，必須輪詢 |
| Transaction.updates 長駐 listener | `AppFeature.onAppear`（`CancelID.transactionUpdates`）| 處理續訂、Ask-to-Buy 核准、退款 demote |
| Foreground re-verify | `AppFeature.scenePhaseChanged(.active)` | 多裝置同步、手動取消後回 App |
| Restore（換機 / 重裝）| `PurchaseClient.restorePurchases` | `AppStore.sync()` + 走 currentEntitlements |
| 過期 transaction 直接 `.finish()` 不打 server | `observeTransactionUpdates` / `verify` / `restore` 三條路徑都有過濾 | 防無窮迴圈打 server 拿 400 |
| Paywall UI、訂閱條款揭露、Privacy / Terms 連結 | `PaywallView`、`Sources/.../Shared/LegalURLs.swift` | App Review 要求 |

### 3.2 Supabase 端負責

| 責任 | 位置 | 備註 |
|---|---|---|
| 驗證 Apple JWS（cert chain + 簽章）| `sync-entitlement/index.ts::verifyAppleJWS` | `@peculiar/x509` + `jose`（取代 Apple 官方 lib，Deno 環境跑不動） |
| Anchor 到 Apple Root G3 | secret `APPLE_ROOT_G3_PEM` | fingerprint `63:34:3A:BF:...:91:79` |
| 區分 Sandbox / Production cert chain | secret `APPLE_ENVIRONMENT` | 上 App Store 前**必須**改 `PRODUCTION` |
| 比對 bundleId / productId / expiresDate | Edge Function 內 | hardcode `com.ininder.ed.latergram` + `.premium.monthly` |
| C3：比對 `appAccountToken == userId` | Edge Function 內 | legacy 無 token 暫時通過 |
| JWS 去重 | `processed_transactions` 表 | 同 transaction_id 重送會跳過 update |
| 升級寫 `profiles`（`is_premium=true, premium_source='iap'`）| Edge Function 升級路徑 | 會覆寫 manual 標記 |
| 降級寫 `profiles`（`is_premium=false`）`.eq('premium_source','iap')` | Edge Function 降級路徑 | 不誤撤 manual |
| Self-heal：清理該 user 過期 manual | Edge Function 進入時跑 | 取代 pg_cron |
| `message_limit` 推導 | trigger `profiles_sync_entitlements` | client 不必知道規則 |
| `delay_seconds` 上限 enforce | trigger `enforce_delay_seconds_limit` | non-premium 送 `delay_seconds > max_delay_seconds` 直接 `delay_seconds_exceeds_free_limit` |
| Manual premium 入帳 | 客服 SQL（service_role）| 三欄位（`is_premium / source / until`）一起改 |

### 3.3 Apple 端

- 發行 JWS（每筆 transaction 帶 ES256 簽章）。
- 維護 cert chain（leaf → intermediate → Apple Root G3）。
- 自動續訂：每 5 分鐘（sandbox）/ 1 個月（production）推一筆新 transaction 到 `Transaction.updates`。
- 取消 / 退款 / Ask-to-Buy 核准：透過 `Transaction.updates` 或 `revocationDate` 通知。
- **不主動通知過期**：到期不會推 event，只能 client 端輪詢 `currentEntitlements`。

---

## 4. 核心流程

### 4.1 升級（首次購買）

```
User 點訂閱按鈕
  ↓
PurchaseClient.purchase(product)
  - 取 session.user.id
  - options: [.appAccountToken(userID)]
  - product.purchase(options:)
  ↓
Apple 彈框 → 用戶確認
  ↓
case .success(.verified(transaction))
  ↓
syncPremium(jws: verification.jwsRepresentation)
  ↓ POST /functions/v1/sync-entitlement  body={"jws":"..."}
Edge Function
  - decode JWT → userId
  - self-heal 過期 manual（這次無事可做）
  - verifyAppleJWS(jws)：cert chain + 簽章
  - 比對 bundleId / productId / expiresDate / appAccountToken
  - INSERT processed_transactions（去重）
  - UPDATE profiles SET is_premium=true, premium_source='iap', premium_until=...
  - Trigger 自動 message_limit=3
  - SELECT profile → 回傳
  ↓
PurchaseClient 收到 profile
  ↓
transaction.finish()  ← 成功才 finish，失敗留 unfinished
  ↓
return profile
  ↓
PaywallFeature._purchaseResult(.success)
  → currentUserClient.update(profile)
  → delegate(.purchaseSucceeded) → parent → AppFeature.profileRefreshed
```

### 4.2 降級（自然到期 / 取消後到期）

> Apple 對「自然到期」**不會**推 `Transaction.updates`。必須靠 client 主動輪詢。

```
觸發點之一：
  - AppFeature.sessionChecked（登入後）
  - AppFeature.scenePhaseChanged(.active)（每次回到 foreground）
  - AppFeature.auth(.succeeded)（剛登入完）
  ↓
PurchaseClient.verifyAndSyncEntitlement()
  - 掃 Transaction.currentEntitlements
  - 過濾：productID match、revocationDate==nil、expirationDate>now、appAccountToken match
  - 找到第一筆有效 → validJWS = jwsRepresentation
  - 都沒有 → validJWS = nil
  ↓
syncPremium(jws: validJWS)
  ↓
Edge Function
  - 有 jws → 升級路徑（同 4.1）
  - 無 jws → 降級路徑：
      UPDATE profiles
        SET is_premium=false, premium_source=null, premium_until=null
        WHERE id=userId AND premium_source='iap'    ← 不誤撤 manual
      Trigger 自動 message_limit=1
  - 回傳 profile（無論升降）
  ↓
profileRefreshed → currentUserClient.update
```

### 4.3 Restore（換機 / 重裝 App）

```
PaywallView 點「還原購買」
  ↓
PurchaseClient.restorePurchases()
  - AppStore.sync()  ← 強制與 Apple 對齊
  - 掃 currentEntitlements（同 4.2 邏輯）
  - 找到第一筆有效 → syncPremium(jws:)
  - 沒找到 → return nil
  ↓
PaywallFeature._restoreResult(.success(.some)) → 升級
                          (.success(.none))    → 顯示「找不到可還原的購買紀錄」
```

### 4.4 Transaction.updates 長駐 listener

```
AppFeature.onAppear
  ↓
.run { for await profile in purchaseClient.observeTransactionUpdates() { ... } }
  .cancellable(id: CancelID.transactionUpdates)
  ↓
for await result in Transaction.updates {
  - guard .verified(transaction)
  - guard productID match → 否則 finish 跳過
  - guard 有 session → 否則跳過不 finish（未登入時不處理）
  - C3：appAccountToken match → 否則跳過不 finish（留給該 user 下次登入）
  - 過期？ → finish 後跳過不打 server（防迴圈）
  - revocationDate==nil ? jws : nil  ← 退款時 jws=nil 走降級
  - syncPremium → 成功才 finish；失敗留待下次 verify
  - yield(profile) → AppFeature.profileRefreshed
}
```

**Listener 命中的場景**：
1. 月訂自動續訂（Apple 推新 transaction）
2. Ask-to-Buy 家長核准後（推核准 transaction）
3. 退款（Apple 推帶 `revocationDate` 的 transaction）
4. 多裝置：另一台買的，這台 listener 也會收到

### 4.5 verifyAndSyncEntitlement 觸發點

| 觸發 | 程式碼 | 為什麼 |
|---|---|---|
| App 起動找回 session | `AppFeature.sessionChecked` | 開 App 第一件事就要對齊 |
| 剛登入成功 | `AppFeature.auth(.succeeded)` | 新登入用戶可能在別處有訂閱 |
| 回到 foreground | `AppFeature.scenePhaseChanged(.active)` | 在背景時可能：訂閱到期、別台手動取消、訂閱續訂失敗 |

**為什麼三條都要**：
- listener 只能接 Apple 主動推的 event，**不接「過期」**。
- 純靠 listener 會漏掉「用戶開 App 時剛好過期」這 case。
- 反過來只靠 verify 不夠：用戶長時間留在 foreground 跨過續訂時刻，listener 才能即時 promote。

### 4.6 Manual Premium 發放（人工）

> **前提**：manual 只對「目前無有效 IAP」的用戶使用。手動 SQL 一定要帶 guard。

`supabase/migrations/20260602120000_manual_premium_grant.sql` 結尾有完整 SQL 範本。摘要：

**Step 1**：用 email 查到 `id`（email 在 `auth.users`，不在 `public.profiles`）

```sql
select u.id, u.email, p.display_name,
       p.is_premium, p.premium_source, p.premium_until
from auth.users u
join public.profiles p on p.id = u.id
where u.email = 'xxx@xxx.com';
```

**Step 2**：用 `id` 改 premium（用 uuid 而非任何人類可讀欄位，避免誤動同名/未來改名造成的歧義）

```sql
-- 永久白名單
update public.profiles
set is_premium = true, premium_source = 'manual', premium_until = null
where id = '11111111-2222-3333-4444-555555555555'
  and (
    premium_source is null
    or premium_source = 'manual'
    or (premium_source = 'iap'
        and (premium_until is null or premium_until < now()))
  );

-- 送 N 天
update public.profiles
set is_premium = true, premium_source = 'manual',
    premium_until = now() + interval '10 days'
where id = '11111111-2222-3333-4444-555555555555'
  and (
    premium_source is null
    or premium_source = 'manual'
    or (premium_source = 'iap'
        and (premium_until is null or premium_until < now()))
  );

-- 撤回（只撤 manual）
update public.profiles
set is_premium = false, premium_source = null, premium_until = null
where id = '11111111-2222-3333-4444-555555555555'
  and premium_source = 'manual';

-- 跑完一定要 select 確認
select id, display_name, is_premium, premium_source, premium_until
from public.profiles
where id = '11111111-2222-3333-4444-555555555555';
```

Guard 的 `or (premium_source='iap' and premium_until<now())` 用意：允許對「IAP 已過期但 row 還沒 self-heal 清掉」的用戶下 manual。

### 4.7 Self-heal（manual 過期清理）

每次 Edge Function 進來，handler 開頭跑：
```sql
UPDATE profiles
   SET is_premium=false, premium_source=null, premium_until=null
 WHERE id = userId
   AND premium_source = 'manual'
   AND premium_until IS NOT NULL
   AND premium_until < now();
```

- 永遠不開 App 的 manual 用戶會「虛胖」（DB 顯示 premium，但他根本沒登入也不會用到）。可接受 — 客服報表用 `where premium_until > now() AND ...` 過濾即可。
- 為什麼不用 pg_cron：少一個元件、少一個排程死鎖風險、self-heal 對「真正用 App 的 user」即時有效已足夠。

---

## 5. 安全防禦

| 防禦 | 在哪 | 防什麼 |
|---|---|---|
| **C1** 撤回 client UPDATE 權限 | migration 20260528 | client 強撤 SQL 直接寫 `is_premium=true` |
| **C1** trigger 推導 `message_limit` | migration 20260528 | client 寫假的 `message_limit=999` |
| **C3** purchase 帶 `appAccountToken=userID` | `PurchaseClient.purchase` | server 可以驗 transaction 屬於該 user |
| **C3** Edge Function 比對 `appAccountToken == userId` | sync-entitlement | 用戶 A 撈 JWS 給用戶 B 升級 |
| **C3** Client 端 currentEntitlements / updates 也比對 token | PurchaseClient 三處 filter | 防把別 user 殘留的 transaction 算到自己頭上 |
| **去重** `processed_transactions` PK | migration 20260528 + Edge Function | 重放同 JWS 不會重寫 |
| **Cert chain** anchor Apple Root G3 | Edge Function `verifyAppleJWS` | 偽造 JWS |
| **Bundle / Product ID 白名單** | Edge Function hardcode | 別 App 的 JWS 拿來騙 |
| **expiresDate** server 端再驗一次 | Edge Function | client 帶過期 JWS 來 |
| **降級 `.eq('premium_source','iap')`** | Edge Function | client 強推空 JWS 撤掉 manual 白名單 |
| **Self-heal manual 過期** | Edge Function 進入時 | 過期 manual 殘留虛胖 |
| **`delay_seconds` 上限 trigger** | migration 20260604 | client `state.isPremium` 快照誤判 / 離線 race / 被改 client 時，非 premium 仍能送出 >24h 訊息 |

**未做**：OCSP 線上撤銷檢查。Deno 環境跑不動同類 Node API。Trade-off：上述多層防禦已足夠。

---

## 6. UI 進入點

### 6.1 觸發 paywall 的位置

| 位置 | 條件 | 程式 |
|---|---|---|
| Compose（拉延遲超過 1 天）| `delaySeconds > maxDelaySeconds`（free=86400）| `ComposeFeature` → `showPaywallHint` → `paywallHintUpgradeTapped` |
| Countdown inbox（達 message 上限再寄）| `messageLimit` 已滿 | `CountdownInboxFeature` 內 `paywall` `@Presents` |
| ChatDetail（同上）| 同上 | `ChatDetailFeature` 內 `paywall` `@Presents` |
| Settings | 已是 premium 顯示「管理訂閱」連結 | `SettingsView`（用 `Link` 不是 `.manageSubscriptionsSheet`，避免 NavigationStack crash） |

### 6.2 Paywall 內

- `onAppear`：同時跑 fetchProducts + verifyAndSyncEntitlement。兩者皆有 **10 秒 client-side timeout**（`purchaseNetworkTimeout`，race 用 `TaskGroup`），任一邊都不可 hang 住 UI。
  - fetchProducts 失敗、timeout、**或回空陣列**（真機斷網 StoreKit 不 throw 直接回 []）→ `productsLoadFailed = true`，UI 顯示錯誤訊息與「重試」按鈕（`retryLoadProductsTapped` 重打）。空陣列在 client 內 throw `.unknown` 統一走失敗路徑。
  - verifyAndSyncEntitlement timeout → 視為 nil entitlement（同既有「找不到有效訂閱」路徑），caller 用 `try? await` 自然消化。
  - 為什麼需要 timeout：`Product.products(for:)` 與 Edge Function 在斷網真機都可能等到 URLSession 預設 ~60s 才 throw。verify 若 hang 還會擋住 retry UI 顯示（view 分支 isVerifyingEntitlement 在 productsLoadFailed 之前）。
- `purchaseTapped`：呼叫 `purchaseClient.purchase` → 成功送 `delegate(.purchaseSucceeded(profile))` 給 parent
- `restoreTapped`：呼叫 `restorePurchases` → 同上
- Privacy Policy / Terms of Use / 訂閱條款揭露（App Review 要求）

### 6.3 Compose snapshot 問題（已知未修）

`ComposeFeature.State` 開 sheet 時帶入 `isPremium` 與 `maxDelaySeconds` 的快照，sheet 開著時付費完成不會即時更新該 sheet。
**目前影響**：付費成功會 dismiss paywall → 通常用戶會重新進 compose，無感。
**未來修法**：parent 在 `profileRefreshed` 後推送更新值進 ComposeFeature，或 `composeTapped` 時重讀 `CurrentUserClient`。

---

## 7. 設計重點與為什麼

### 7.1 為什麼 manual 跟 IAP 不該並存

- 兩者共用 `is_premium` 這個主開關。如果允許並存（例：source=both），降級邏輯會變很麻煩——IAP 到期該不該降？
- 互斥模型下，**source 永遠回答「現在是誰在養著這個 premium 狀態」**。語意乾淨。

### 7.2 為什麼降級路徑加 `.eq('premium_source','iap')`

- 降級 trigger = client 端 `verifyAndSyncEntitlement` 沒找到有效 IAP entitlement 時呼叫，空 body。
- 如果不加 filter，會把 manual 白名單也一起降掉 — 客服剛剛才送出去的補償馬上被擦。
- 加了 filter，意義是：「我（client）只能對 IAP 來源負責，manual 來源請走 SQL 管」。

### 7.3 為什麼 IAP 升級會覆寫 manual

- 因為 IAP 是「真實付費」，是最強的事實。如果一個白名單用戶決定自己訂閱，他付的錢必須被認帳。
- 副作用：**白名單「失憶」** — 等他 IAP 到期會降回 free，原本的 manual 白名單身份不會自動恢復。
- Trade-off 已接受。客服需求出現時手動再加一次。

### 7.4 為什麼用 Edge Function 而不是 RLS policy

- RLS 無法做 cert chain 驗證、無法呼叫外部 API、無法跑 ES256 簽章驗。
- 必須走 Edge Function 才能在 server side 跑 `@peculiar/x509` + `jose`。
- Client 直接 UPDATE 即使加再嚴的 RLS policy 也只能驗 `auth.uid()`，無法驗「這筆 transaction 是 Apple 簽的」。

### 7.5 為什麼不用 Apple 官方 `@apple/app-store-server-library`

- 該 lib 依賴 Node-only crypto API（`X509Certificate.prototype.toString` / `.raw`）。
- Supabase Edge Functions 跑在 Deno 上，這些 API 沒實作 → import 即炸。
- 改用 `@peculiar/x509`（cert chain 用 Web Crypto）+ `jose`（ES256 簽章驗證）做同樣的事。

### 7.6 為什麼不開 pg_cron

- 少一個元件 / 排程 / 監控負擔。
- self-heal 對「真正用 App 的用戶」即時有效已足夠。
- 永遠不開 App 的虛胖 row 不影響其他 user、不會被誤計費。客服查 active premium 數量時 SQL 加 `where premium_until > now() or premium_until is null` 即可。

### 7.7 為什麼 `transaction.finish()` 要在 sync 成功才呼叫

- finish 後 Apple 不會再推這筆 transaction 也不在 `currentEntitlements`。
- 若 sync 失敗（網路斷、Edge Function 500）就 finish，這筆 entitlement 等於丟了。
- 留 unfinished → 下次 `verifyAndSyncEntitlement` 從 `currentEntitlements` 重新撿回 → 重試 sync。

### 7.8 為什麼 expired transaction 直接 `.finish()` 不打 server

- StoreKit 2 `currentEntitlements` 理論上只回有效 entitlement，但 sandbox 環境會殘留過期的（曾踩過）。
- 若把過期 JWS 送 server，server 會回 400 `expired`，client 沒 finish → 下次 listener / verify 又抓到同筆 → 無窮迴圈打 server 拿 400。
- 過濾 `expirationDate > now`，過期的直接 finish 清掉。真實 entitlement 狀態由 `verifyAndSyncEntitlement` 整體計算決定升 / 降。

### 7.9 為什麼 client 也要驗 `appAccountToken`（不只 server 驗）

- 防禦縱深。
- Server 端因 legacy 訂閱可能沒 token 而暫時放行，client 端也跟著這條規則（`if let token = ..., token != userID { continue }`）。
- 多裝置 / 多帳號的雜質 transaction 不會被算到當前 user。

---

## 8. Cases 全排列組合

> 標記說明：
> - 「→」表示「結果」
> - 「⚠️」表示已知限制或副作用
> - 「✅」表示測過 / 設計上正確
> - 「🔲」表示尚未實作或未測過的場景

### A. IAP 訂閱生命週期

#### A1. 首次購買（free → premium via IAP）
- 觸發：Paywall「訂閱」
- 路徑：4.1
- DB 結果：`is_premium=true, premium_source='iap', premium_until=expires, message_limit=3`
- ✅ 已測（2026-06-02 sandbox）

#### A2. 月訂自動續訂（premium → premium 延長）
- 觸發：Apple 推 `Transaction.updates`（sandbox 每 5 分鐘）
- 路徑：4.4 → syncPremium 升級
- DB 結果：`premium_until` 推遲一個月
- `processed_transactions` 新增一筆（新 transactionId、同 originalTransactionId）
- ✅ 已測

#### A3. 用戶在 Apple 端取消（仍在期間內）
- 觸發：用戶 Settings → Apple ID → Subscriptions → Cancel
- 期間內：Apple 不推任何 event，仍是 premium
- 期間到：不會推 event，但 `currentEntitlements` 不再回這筆
- App 下次 `verifyAndSyncEntitlement`（foreground / 登入）→ 找不到有效 → POST 空 body → 降級
- DB 結果：`is_premium=false, premium_source=null, premium_until=null, message_limit=1`
- ✅ 設計上正確（sandbox 流程已驗）

#### A4. 自然到期（用戶從沒主動取消，續訂失敗）
- 同 A3 後半段。
- Apple 不推 event；靠 client foreground verify 降級。

#### A5. 退款 (refund)
- 觸發：用戶 App Store 申請退款 → Apple 核准
- Apple 推 `Transaction.updates` 帶 `revocationDate`
- Listener (4.4) `isActive = (revocationDate==nil)` → false → `jws=nil` → 走降級路徑
- DB 結果：`is_premium=false, premium_source=null`
- ✅ 設計上正確（未實測；A1 commit `67e4466` cover）

#### A6. Ask-to-Buy（家長尚未核准）
- 購買 result = `.pending`
- `PurchaseError.pending` → paywall 顯示「購買待審核中」
- 家長核准 → Apple 推 `Transaction.updates` → listener 自動 promote
- 家長拒絕 → 不推任何東西，paywall 不會再升級
- ✅ 設計上正確（未實測）

#### A7. Sandbox 縮時續訂 5 次後 Apple 自動取消
- Apple sandbox 月訂 = 5 分鐘，續 5 次後自動取消
- 同 A4
- ✅ 已測

#### A8. Billing retry / grace period
- 信用卡刷不過 → Apple 進 retry。
- 目前未判斷 `SubscriptionInfo.RenewalState.inBillingRetryPeriod`，視為「沒 entitlement」→ 降級。
- 🔲 P3 待補（IAP_TODO E3）

#### A9. Family Sharing（家庭共享訂閱）
- 訂閱者買 → 家庭成員自動有 entitlement
- 該成員的 `currentEntitlements` 會有這筆 transaction，但 `appAccountToken` 可能是訂閱者的 uid
- C3 比對 `token != userID` → client 過濾掉 → 不會升級
- 結果：**家庭成員無法享受 premium**
- 🔲 設計上未支援；目前不是需求

### B. Manual 生命週期

#### B1. 永久白名單（free → manual 無期限）
- 觸發：客服跑 `is_premium=true, source='manual', premium_until=null`
- DB 結果：`is_premium=true, premium_source='manual', premium_until=null, message_limit=3`
- App 端下次 verify：不影響 — Edge Function 升級才會碰 source，**降級時** `.eq('source','iap')` 會略過 manual
- ✅ 設計上正確

#### B2. 限時補償 N 天（free → manual N 天）
- 同 B1，但 `premium_until = now() + interval 'N days'`
- N 天後用戶任何 Edge Function 呼叫（包括 foreground verify）→ self-heal 清掉
- ✅ 設計上正確

#### B3. 撤回 manual（manual → free）
- 觸發：客服跑 `is_premium=false, source=null, premium_until=null where source='manual'`
- guard `source='manual'` 防誤撤 IAP
- ✅ 設計上正確

#### B4. manual 期間用戶從沒開 App
- self-heal 不會跑 → `is_premium=true` 持續到永遠
- ⚠️ 已知接受。客服報表用 `where premium_until > now() OR premium_until IS NULL` 過濾。

#### B5. manual 用戶按下「訂閱」想自己付費
- C 區會詳細討論。簡述：source 變 `iap`，原 manual 紀錄被覆寫，IAP 到期後白名單「失憶」。

### C. Manual × IAP 排列組合

> 假設 user U，狀態以 `(is_premium, source, until)` 表示。

#### C1. (free) → IAP 訂閱
- 結果：`(true, iap, +1月)`
- 同 A1

#### C2. (free) → manual N 天
- 結果：`(true, manual, +N天)`
- 同 B2

#### C3. (manual 永久) → 用戶自己訂閱 IAP
- 路徑：升級路徑無 source filter → 直接 overwrite
- 結果：`(true, iap, +1月)`
- ⚠️ 原 manual 永久白名單身份「遺失」
- IAP 到期後 → 降回 `(false, null, null)`
- 客服若想回復白名單需重新跑 SQL

#### C4. (manual N 天) → 用戶自己訂閱 IAP
- 同 C3
- 用戶其實虧 — 本來能免費用 N 天再開始訂閱
- 不會自動退款 / 提示。
- 🔲 未來 P3 可加 paywall「您已是會員（限期 N 天）」提示（IAP_TODO D3）

#### C5. (IAP 進行中) → 客服誤對他下 manual
- 手動 SQL guard 會擋掉：`where ... or (source='iap' and until < now())`
- 沒有 row 會被 update
- ✅ 客服跑完一定要 select 確認

#### C6. (IAP 已過期，但 row 還沒被 client verify 降回 free) → 客服下 manual
- guard 第三條：`source='iap' AND until<now()` ✅ 命中
- update 成功 → `(true, manual, ?)`
- ✅ 設計上正確（自動取代 IAP）

#### C7. (manual 永久) 同時手機在 background → IAP 訂閱被退款
- 退款 → listener 收到 `revocationDate` → `jws=nil` → 降級路徑 `.eq('source','iap')`
- manual row source='manual' → 不命中 filter → **不會被誤撤** ✅
- 結果：`(true, manual, null)` 維持

#### C8. (manual N 天到期當下) 同時用戶開 App
- Edge Function 進入時 self-heal → `(false, null, null)`
- 接著 verifyAndSyncEntitlement 跑：找不到 IAP → 降級 path `.eq('source','iap')` 0 row 改動
- 結果：`(false, null, null)` ✅

#### C9. (manual 過期 + IAP 同時被買) — 罕見競態
- Edge Function 進入時 self-heal 先清 manual → `(false, null, null)`
- 接著 jws 升級 → `(true, iap, +1月)`
- ✅ 順序正確（self-heal 在 jws 處理之前）

#### C10. (IAP 即將到期最後一秒) 客服送 manual 30 天
- 客服跑 SQL：guard `source='iap' AND until<now()` — 此時 `until>now()` 仍有效 → 沒命中、沒 update
- 客服需等 IAP 自然過期，或暫時用「先撤 IAP（不可）→ 加 manual」（不能撤 IAP，會破壞語意）
- ⚠️ Trade-off：客服遇此案要等 IAP 到期或自行決定 SQL 跳過 guard（service_role 可繞）

#### C11. (用戶持有「無 expiry 的 IAP」legacy) → 升級時 `premium_until=null`
- 升級成功，row = `(true, iap, null)`
- 降級時 verify 找不到該 entitlement → 走降級，正常清掉
- ✅ 邏輯支援，但目前產品只賣 monthly subscription，不會有此 case

### D. 多裝置 / 跨帳號 / 跨平台

#### D1. 用戶 A 兩台 iPhone 都登入
- A 在裝置 1 訂閱 → 裝置 1 走 4.1 升級
- 裝置 2：
  - 若 foreground 中：scenePhase 不會觸發 → 仍是 free 直到下次回 foreground
  - listener 不一定會收到（Apple 對「別處購買」**有時**會推到所有裝置）
  - 用戶切回 foreground → `verifyAndSyncEntitlement` → 找到 entitlement → 升級
  - 或用戶手動「還原購買」也行
  - **若用戶在裝置 2 cache stale 期間打開 paywall**（例如 A、B 同時前景）：paywall onAppear 會跑 `verifyAndSyncEntitlement`，發現已是 premium 後切換成「您已是 Premium 會員」確認畫面（含管理訂閱連結），避免引導重複購買。用戶按「完成」後 paywall dismiss + 本地立刻拿到 premium 權限。
- ✅ 設計上 cover

#### D2. 用戶 A 同時開兩個 paywall
- Compose sheet 內 paywall + 另一條 path 進 ChatDetail paywall — 不會發生（modal 互斥）
- 但 background 跑 listener 同時用戶手動 purchase → 兩條路徑都會打 syncPremium
- `processed_transactions` 去重 → 第二筆 select existing 命中 → 不重複 insert
- profile update 第二次重寫成同樣值 → no-op
- ✅ 安全

#### D3. iPad / Mac Catalyst（未來）
- 同 D1 邏輯
- bundle id 不變即可

#### D4. 跨 Apple ID（用戶 A 換 Apple ID）
- 換 Apple ID 後 `currentEntitlements` 為空 → 走降級
- 用戶要靠「還原購買」與 Apple 對齊（但新 Apple ID 沒這筆 transaction）
- 結果：除非新 Apple ID 自己再訂閱，否則 free
- ✅ 設計上正確（Apple 訂閱本就綁 Apple ID）

#### D5. 跨 Latergram 帳號（用戶在同一台 iPhone 切換登入 A / B）
- A 在這台買訂閱（appAccountToken=A）
- B 登入後 listener 收到 transaction：`token != B` → 跳過不 finish
- B 用 verifyAndSyncEntitlement：currentEntitlements 仍有這筆，但 token != B → 過濾掉 → 降級
- 結果：B 不會被誤升級為 premium ✅（C3 防禦）

### E. 錯誤路徑

#### E1. Apple JWS 驗證失敗
- 例：APPLE_ENVIRONMENT 設成 PRODUCTION 但跑 sandbox
- Edge Function 回 400 `invalid jws`
- Client `purchase` throws → paywall 顯示「購買驗證失敗」
- `transaction.finish()` 沒呼叫 → 下次 verify 重試
- ⚠️ 真實沙箱跑這條會死循環（每次 verify 都打 server 拿 400）— 由 expirationDate 過濾解決（過期才不打）
- 若 JWS 仍有效但 server 設定錯，會持續失敗直到 server 修好

#### E2. Edge Function 500（DB 寫入失敗）
- Client `purchase` throws → 失敗
- `transaction` 不 finish → 下次 verify 撿回
- `processed_transactions` 已 insert（先做 dedup），但 profiles update failed → 不一致狀態
- 🔲 已知微小一致性風險（dedup 先 insert / profile update 後做）— 影響：同 transaction 下次重試會走 `if (!existing)` false branch → 跳過 dedup 直接 update profile → 修復
- ✅ 可自癒

#### E3. C3 appAccountToken 不符
- Edge Function 回 400 `appAccountToken mismatch`
- Client `purchase` throws
- 不該在正常流程發生（除非有人在 attack）
- ✅ 設計上正確（測試見 IAP sandbox test plan 階段 6）

#### E4. Bundle / Product ID 不符
- Edge Function 回 400 `bundle mismatch` / `product mismatch`
- 攻擊者拿別 App 的 JWS 騙
- ✅ 擋下

#### E5. JWS expired（過期 transaction）
- 正常情況：client 已過濾過期 transaction 不打 server
- 萬一漏網：server 回 400 `expired`
- ✅ 雙層防禦

#### E6. 網路斷
- `purchase` / `verify` / `restore` 全部 throws
- Transaction 留 unfinished → 下次 verify 撿回
- Paywall 顯示錯誤訊息

#### E7. Supabase Auth session 過期
- `supabase.auth.session` throws
- listener 跳過該筆不 finish；purchase 路徑直接 throws
- 用戶重新登入後 → `auth(.succeeded)` → 跑 verify → 撿回

#### E8. APPLE_ENVIRONMENT 設錯（上線前忘記改）
- Sandbox cert chain 驗 production JWS → cert chain mismatch → 400
- ⚠️ **所有真實付費用戶 is_premium 不會被寫入**
- ✅ 已記在 [[project-app-store-pre-submission]]、IAP_TODO

#### E9. `processed_transactions` 寫入失敗（DB FK 約束 / 連線斷）
- Edge Function 回 500 `dedup insert failed`
- Client 重試（同 E2）

#### E10. 退款後仍在 expiration date 內
- Apple 推 `revocationDate` 早於 `expirationDate`
- Listener `isActive=false` → 走降級
- ✅

#### E11. 用戶刪除 App 又重裝
- 重裝後 `currentEntitlements` 仍有效（StoreKit 與 Apple ID 綁定）
- 重新登入 → `verifyAndSyncEntitlement` → 找到 → 升級
- Restore 不必要但也可走
- ✅

#### E12. 登出後其他 user 用同一台 App 登入
- 登出時 currentUserClient 重置（CLAUDE.md 規則 1）
- 新 user 走 sessionChecked → verify → 自己的 entitlement
- 若舊 user 的 transaction 還在 listener queue：token != newUser → 跳過 ✅

---

## 9. Edge Cases 清單

> 所有「值得記」的邊界 case，照影響嚴重度排序。**狀態欄**：✅ 設計上 cover、⚠️ 已知 trade-off、🔲 未實作 / 未測。

| # | Case | 觸發條件 | 目前行為 | 狀態 |
|---|---|---|---|---|
| 1 | 過期 JWS 死循環 | sandbox 殘留過期 transaction 沒 finish | client 三條路徑都過濾 `expirationDate > now`，過期直接 finish 不打 server | ✅ |
| 2 | sync 失敗丟 entitlement | 網路斷 / Edge Function 500 | `transaction.finish()` 在 sync 成功才呼叫，失敗保留 unfinished | ✅ |
| 3 | 多裝置別處購買 | 裝置 A 訂閱 → 裝置 B 是 free | scenePhase active 觸發 verify；Apple 有時推 listener | ✅ |
| 4 | C3 跨帳號污染 | 用戶 A 撈自己 JWS 給用戶 B 補 | Edge Function 比 `appAccountToken=userId` 擋下 400 | ✅ |
| 5 | C3 同台多登入 | A 登出 / B 登入 / listener 收到 A 的 transaction | client 端 filter `token != currentUser` 跳過 | ✅ |
| 6 | manual 白名單被 IAP 覆寫 | manual 用戶自己訂閱 | source 變 `iap`，IAP 到期後降回 free，「失憶」 | ⚠️ 接受 |
| 7 | manual 用戶從沒開 App | self-heal 不會跑 | `is_premium=true` 持續到永遠（虛胖） | ⚠️ 接受 |
| 8 | 客服在 IAP 進行中誤下 manual | guard 阻擋 | SQL 0 row 改動，客服需 select 確認 | ✅ |
| 9 | C10：客服想在 IAP 即將到期前疊加 manual | guard 不命中 | 需等 IAP 自然過期 | ⚠️ 接受 |
| 10 | IAP 升級時剛好 manual 過期 | self-heal + JWS 升級同一個 request | self-heal 先跑，再 jws 升級，順序正確 | ✅ |
| 11 | 退款（revocationDate）| Apple 推 update | listener `jws=nil` 走降級，`.eq('source','iap')` 不誤撤 manual | ✅ |
| 12 | 降級擦掉 manual | 不應發生 | 降級 path 有 `.eq('source','iap')` 保護 | ✅ |
| 13 | Apple 不推「過期」event | 訂閱自然到期 | foreground re-verify + 登入時 verify cover | ✅ |
| 14 | Ask-to-Buy 家長未核准 | result = `.pending` | UI 顯示「待審核」，核准後 listener 自動 promote | ✅ |
| 15 | Family Sharing 家庭成員 | 該成員 token != 自己 | 被 C3 filter 過濾，**無法享 premium** | 🔲 未支援 |
| 16 | Compose snapshot 不即時更新 | sheet 開著時付費 | 付費成功會 dismiss paywall，但 compose state 仍是舊的 | 🔲 影響低，P3 |
| 17 | Billing retry / grace period | 卡刷不過 | `SubscriptionInfo.RenewalState.inBillingRetryPeriod` 未判斷，視為 free | 🔲 P3 |
| 18 | Paywall fetchProducts 失敗、hang、或回空陣列 | 網路斷 / Apple 慢回應 / 真機斷網 StoreKit 不 throw 直接回 [] | 10 秒 timeout race + 空陣列也視為失敗 → 顯示錯誤訊息 + 「重試」按鈕 | ✅ |
| 19 | 購買中關閉 paywall sheet | `@Presents` dismiss | `isPurchasing` / `isRestoring` 時 X 鈕 disabled + `interactiveDismissDisabled(true)` + 顯示「交易處理中，請勿關閉」提示，直接擋住主動關閉；`observeTransactionUpdates` listener 為最後保險 | ✅ |
| 20 | APPLE_ENVIRONMENT 設錯（送審前忘改）| Sandbox secret 配 Production 真實購買 | 所有 JWS 驗失敗 → 用戶付錢但沒 premium | ⚠️ 已記 pre-submission |
| 21 | bundle / product ID 改名 | hardcode 在 Edge Function | 全部 400 mismatch | ⚠️ 改名需同步改 Edge Function 與 sandbox secret |
| 22 | `processed_transactions` 同 originalTransactionId 連續續訂 | 自動續訂多次 | 每筆 transactionId 不同，去重不命中 → 正常插入 | ✅ |
| 23 | client 強撤 SQL update is_premium | malicious app | RLS 撤回 update 權限，會丟 permission denied | ✅ |
| 24 | client 強撤 SQL update message_limit | malicious app | 同上撤回 | ✅ |
| 25 | client 強撤 SQL update display_name | 正常路徑 | 白名單授權通過 | ✅ |
| 26 | 切換 Apple ID 後 entitlement 消失 | 用戶換 iCloud 帳號 | 走降級為 free；新 Apple ID 自行訂閱才會再升 | ✅ |
| 27 | 換機重裝 App | 同一 Apple ID 登入 latergram | `verifyAndSyncEntitlement` 找回 currentEntitlements 即升級 | ✅ |
| 28 | 登出後新 user 用同台 | A 登出、B 登入 | currentUserClient 已重置；listener filter token | ✅ |
| 29 | JWS legacy 無 `appAccountToken` | 舊訂閱、家庭共享、refund 後重發 | client / server 都暫時放行（後續可能收緊） | ⚠️ |
| 30 | 同一 originalTransactionId 跨 user 出現 | 不該發生（C3 擋）| C3 mismatch 400 | ✅ |
| 31 | Edge Function self-heal 寫失敗 | DB transient 錯誤 | 沒 retry；下次呼叫再清 | ⚠️ 影響低 |
| 32 | Edge Function profile fetch 最終失敗 | 寫成功但 select 失敗 | 回 500，client throws，下次 verify 撿回（state 其實已對） | ⚠️ 影響低 |

---

## 附：常用查詢 SQL

```sql
-- 用 email 查 user id（email 在 auth.users，不在 public.profiles）
select u.id, u.email, p.display_name
from auth.users u
join public.profiles p on p.id = u.id
where u.email = 'xxx@xxx.com';

-- 查某用戶當前 entitlement
select id, display_name, is_premium, message_limit, premium_source, premium_until
from public.profiles
where id = '11111111-2222-3333-4444-555555555555';

-- 查某用戶最近 transaction
select transaction_id, original_transaction_id, product_id, expires_date, processed_at
from public.processed_transactions
where user_id = '11111111-2222-3333-4444-555555555555'
order by processed_at desc limit 10;

-- 全站當前 active premium 統計
select premium_source, count(*)
from public.profiles
where is_premium = true
  and (premium_until is null or premium_until > now())
group by premium_source;

-- 找虛胖 manual（永遠不開 App）
select id, display_name, premium_until
from public.profiles
where premium_source = 'manual'
  and premium_until is not null
  and premium_until < now();
```

## 關聯文件

- `MVP_DECISIONS.md` — IAP 架構決策（Edge Function + JWS + column grant 白名單）
- `TEST_PLAN.md` — 含 IAP sandbox 測試清單
- `PRODUCT_REQUIREMENTS.md` — premium 產品差異化（messageLimit、maxDelaySeconds）
- Memory `project-iap-todo` — 進度清單與 P2/P3 待辦
- Memory `project-iap-sandbox-test-plan` — sandbox 操作手冊
- Memory `project-manual-premium-grant` — manual 發放手動操作摘要
- Memory `project-app-store-pre-submission` — 送審前必做（APPLE_ENVIRONMENT 切 PRODUCTION）
- Memory `project-compose-premium-snapshot` — Compose snapshot 已知問題
