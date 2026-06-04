-- =====================================================================
-- Q2: Server-side delay_seconds guard
--   非付費用戶送訊息時，server 端確認 delay_seconds ≤ max_delay_seconds
--   （預設 24h），避免 client trust 失敗（isPremium 快照誤判 / 暫時離線 /
--   惡意改 client）時繞過免費版上限。
--
--   Trigger 與 check_friend_message_limit 同層級：BEFORE INSERT on messages
--   raise exception 後 client 端轉成「免費版上限 24h」提示。
--
--   Premium 用戶不檢查上限（max_delay_seconds 由 sync-entitlement 維護）。
-- =====================================================================

create or replace function public.check_delay_seconds_limit()
returns trigger as $$
declare
    sender_is_premium bool;
    sender_max_delay int;
begin
    select is_premium, max_delay_seconds
      into sender_is_premium, sender_max_delay
      from public.profiles
      where id = new.sender_id;

    if not sender_is_premium and new.delay_seconds > sender_max_delay then
        raise exception 'delay_seconds_exceeds_free_limit';
    end if;

    return new;
end;
$$ language plpgsql;

create trigger enforce_delay_seconds_limit
    before insert on public.messages
    for each row execute function public.check_delay_seconds_limit();
