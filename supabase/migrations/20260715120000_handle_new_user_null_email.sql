-- =====================================================================
-- handle_new_user：容忍 NULL email
--
-- 動機：
--   Sign in with Apple「重複授權」時（同一 Apple ID 先前已授權過此 App，
--   例如使用者刪了 App 內帳號但沒在 Apple ID 端撤銷授權），Apple 不再
--   釋出 email → idToken 無 email → auth.users.email 為 NULL。
--
--   原 trigger 用 split_part(new.email,'@',1) 當 display_name 預設值，
--   而 split_part(NULL,...) 回傳 NULL，塞進 `display_name text not null`
--   會違反約束 → trigger 拋錯 → 連帶 auth.users 的 insert 一起 rollback
--   → 使用者完全建立不起來（Authentication 什麼都沒有）。
--
-- 修法：
--   NULL / 空 email 時退回「空字串」。空字串滿足 NOT NULL，且 App 端
--   signInWithApple 會把「display_name 為空」判為「尚未取名」→ 導到 setName
--   頁請使用者自行輸入，不會讓空名字外流到主畫面。
--
-- 註：這只解決「能不能建立起來」。要讓刪帳號後能「乾淨重新註冊並拿回
--   email」，仍需在刪帳號流程呼叫 Apple 的 token revoke（見 app 端 TODO），
--   那也是 App Store 5.1.1(v) 對 Sign in with Apple 的要求。
-- =====================================================================

create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(nullif(split_part(new.email, '@', 1), ''), '')
    );
    return new;
end;
$$ language plpgsql security definer;
