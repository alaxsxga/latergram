-- =====================================================================
-- 移除 profiles.username 欄位
--
-- 動機：
--   - 目前 codebase 對 username 純寫入、零讀取（沒有任何 UI、business
--     logic、其他表 FK 用到它），是個死欄位。
--   - 原 handle_new_user trigger 用 split_part(email,'@',1) 當預設值，
--     不同 email 但 local-part 相同（alice@a.com / alice@b.com）會撞
--     unique constraint，導致第二位用戶完全無法註冊。
--   - 與其修 collision 維護死欄位，不如直接拿掉；未來真要做
--     @username 公開 handle，那時應該讓用戶自選而非 auto-generate。
--
-- 部署順序：
--   App Swift 端同步移除 username 寫入（DTO / select 字串）後，再跑此
--   migration。否則舊版 App 對 profiles.select(...) 仍會請求 username，
--   server 會回 column 不存在 → 400。
-- =====================================================================

-- 1. 先重寫 trigger（不再寫 username）。先動函式再 drop 欄位是為了避免
--    drop 那一刻有新註冊湧入時 trigger 仍引用已不存在的欄位。
create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        split_part(new.email, '@', 1)
    );
    return new;
end;
$$ language plpgsql security definer;

-- 2. 移除欄位（unique constraint 會被 cascade 一併刪除）
alter table public.profiles drop column username;
