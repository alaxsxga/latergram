# Latergram

一個「延遲顯示訊息」的好友通訊 iOS App。發送訊息後，對方要等到你設定的時間到了才能點擊開啟。

## 技術

- SwiftUI + TCA (The Composable Architecture)
- Supabase（Auth、Database、RLS、RPC）
- Swift Package Manager

## 設定

1. 複製金鑰範本：
   ```bash
   cp Sources/LatergramPrototype/Infrastructure/Secrets.swift.example \
      Sources/LatergramPrototype/Infrastructure/Secrets.swift
   ```
2. 填入你的 Supabase URL 與 anon key
3. 在 Supabase SQL Editor 執行 `supabase/schema.sql`
4. 用 Xcode 開啟 `Latergram.xcodeproj`，選擇 Simulator，Build & Run

## 專案結構

```
Sources/LatergramCore/        純 Swift，Domain 與規則
Sources/LatergramPrototype/   TCA Features、Dependencies、UI
Tests/LatergramCoreTests/     Domain 單元測試
supabase/schema.sql           資料庫 Schema 與 RLS
```

## 訊息數量限制（Per-Friend Message Limit）

每位用戶對同一好友，同時最多只能有 N 則「尚未解鎖」的 scheduled 訊息。

**預設值：1 則**

達到上限後：
- Toolbar「建立訊息」按鈕改為顯示最早一則訊息的倒數計時，並 disabled
- 側邊出現「解鎖更多」按鈕（目前 disabled，預留 IAP）

### 調整上限

**單一用戶（測試／管理）**：在 Supabase Dashboard → Table Editor → `profiles` 直接修改該 user 的 `message_limit` 欄位。

**SQL 方式**：
```sql
-- 將特定用戶上限改為 3
update profiles set message_limit = 3 where id = '<user-uuid>';

-- 將所有用戶上限改為 3
update profiles set message_limit = 3;
```

### 測試步驟

1. 將自己帳號的 `message_limit` 設為 `1`（預設即是）
2. 登入 App，進入任一好友的聊天頁
3. 傳送一則訊息（unlock_at 設 1 分鐘後）→ 成功，Toolbar 立即變成倒數並 disabled
4. 嘗試再次點「建立訊息」→ 按鈕已 disabled，無法進入 compose
5. 在 Supabase 將 `message_limit` 改為 `2` → **重新登入** App（讓 session 重抓 profile）
6. 進入同一聊天頁 → 按鈕恢復「建立訊息」，可再傳一則
7. 等待第一則訊息的 unlock_at 到達 → 倒數消失，按鈕恢復正常
8. Server-side guard 測試：直接用 Supabase SQL 插入超額訊息 → trigger 應拋 `friend_message_limit_exceeded`
