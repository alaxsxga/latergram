-- Only allow soft-deleting messages that have been revealed.
-- Scheduled and ready-to-reveal messages cannot be deleted by either sender or receiver.
drop policy if exists "message_deletions: 只能新增自己的（時間已到）" on public.message_deletions;
drop policy if exists "message_deletions: 只能新增自己的" on public.message_deletions;

create policy "message_deletions: 只能新增自己的"
    on public.message_deletions for insert
    with check (
        auth.uid() = user_id
        and exists (
            select 1 from public.messages m
            where m.id = message_id
              and (m.sender_id = auth.uid() or m.receiver_id = auth.uid())
              and m.status = 'revealed'
        )
    );
