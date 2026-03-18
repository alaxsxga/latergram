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
