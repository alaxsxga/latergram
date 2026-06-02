-- =====================================================================
-- C1: Server-side entitlement guard
--   1) 撤回 client 端對敏感欄位（is_premium / message_limit / max_delay_seconds）
--      的 update 權限 → 防止 client 直接 UPDATE profiles SET is_premium=true 假升級
--   2) is_premium 變動時，自動同步 message_limit（trigger）
--   3) 新增 processed_transactions 表，供 Edge Function 去重 / 對帳稽核
--
-- 部署前提：sync-entitlement Edge Function 已部署且可用
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 收緊 profiles 表的 update 權限（白名單模式）
-- ---------------------------------------------------------------------
--   撤回 authenticated 對整張表的 update，
--   只授權 display_name 一個欄位。
--   - username：unique 欄位，目前無 UI 也無 server-side 驗證，刻意不開
--   - is_premium / message_limit / max_delay_seconds：entitlement，
--     僅可由 service_role（Edge Function）或 trigger 寫入
revoke update on public.profiles from authenticated;

grant update (display_name) on public.profiles to authenticated;

-- ---------------------------------------------------------------------
-- 2. is_premium → message_limit 推導 trigger
-- ---------------------------------------------------------------------
--   policy：
--     premium = true  → message_limit = 3
--     premium = false → message_limit = 1
--
--   未來限時優惠或調整數字，只需 CREATE OR REPLACE 本函式並對既有 premium
--   用戶執行一次 no-op update 觸發 trigger：
--     UPDATE profiles SET is_premium = is_premium WHERE is_premium = true;
create or replace function public.sync_premium_entitlements()
returns trigger as $$
begin
    -- 僅在 is_premium 確實變動時生效，避免不必要寫入
    if new.is_premium is distinct from old.is_premium then
        if new.is_premium then
            new.message_limit := 3;
        else
            new.message_limit := 1;
        end if;
    end if;
    return new;
end;
$$ language plpgsql;

-- BEFORE UPDATE 直接改 NEW，避免再次觸發 trigger（無遞迴風險）
create trigger profiles_sync_entitlements
    before update of is_premium on public.profiles
    for each row
    execute function public.sync_premium_entitlements();

-- ---------------------------------------------------------------------
-- 3. processed_transactions：防 JWS 重放 + 對帳稽核
-- ---------------------------------------------------------------------
create table public.processed_transactions (
    transaction_id text primary key,
    original_transaction_id text not null,
    user_id uuid not null references public.profiles(id) on delete cascade,
    product_id text not null,
    expires_date timestamptz,
    processed_at timestamptz not null default now()
);

create index idx_processed_transactions_user_id
    on public.processed_transactions(user_id);
create index idx_processed_transactions_original
    on public.processed_transactions(original_transaction_id);

-- RLS：authenticated 完全不可讀寫；service_role bypass RLS 仍可正常操作
alter table public.processed_transactions enable row level security;
-- 故意不建立任何 policy → 對 authenticated 預設拒絕全部操作
