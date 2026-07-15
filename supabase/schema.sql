-- =====================
-- 1. profiles
-- =====================
create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null,
    message_limit int not null default 1,          -- 每位好友最多可同時 scheduled 的訊息數
    is_premium bool not null default false,
    premium_source text check (premium_source in ('iap', 'manual')),  -- entitlement 來源
    premium_until timestamptz,                     -- entitlement 到期日；null = 無限期（永久白名單）
    max_delay_seconds int not null default 86400,  -- 免費版 24h；付費版可動態調整
    created_at timestamptz not null default now()
);

-- 新用戶註冊時自動建立 profile
create or replace function public.handle_new_user()
returns trigger as $$
begin
    -- NULL email（Apple 重複授權不再釋出 email）時退回空字串：滿足 NOT NULL，
    -- 且 App 端會把空 display_name 判為「尚未取名」→ 導到 setName 頁自行輸入。
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(nullif(split_part(new.email, '@', 1), ''), '')
    );
    return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- =====================
-- 2. friendships
-- =====================
create table public.friendships (
    id uuid primary key default gen_random_uuid(),
    requester_id uuid not null references public.profiles(id) on delete cascade,
    addressee_id uuid not null references public.profiles(id) on delete cascade,
    status text not null default 'pending'
        check (status in ('pending', 'accepted', 'rejected', 'blocked')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (requester_id, addressee_id)
);

-- =====================
-- 3. messages
-- =====================
create table public.messages (
    id uuid primary key default gen_random_uuid(),
    sender_id uuid not null references public.profiles(id) on delete cascade,
    receiver_id uuid not null references public.profiles(id) on delete cascade,
    body text not null,
    message_type text not null default 'delayed'
        check (message_type in ('delayed', 'instant')),
    style_key text not null
        check (style_key in ('classic', 'warm', 'cool', 'heart')),
    unlock_at timestamptz,
    delay_seconds int not null check (delay_seconds >= 60),
    status text not null default 'scheduled'
        check (status in ('scheduled', 'ready_to_reveal', 'revealed')),
    revealed_at timestamptz,
    created_at timestamptz not null default now()
);

-- =====================
-- 4. invite_tokens
-- =====================
-- 備註：一個 token 可被多人使用，每位 user 同時只能有一個 token
-- 產生新 token 前會先刪除舊的，「失效」按鈕也直接刪除
create table public.invite_tokens (
    id uuid primary key default gen_random_uuid(),
    token text unique not null default generate_short_invite_code(),
    inviter_id uuid not null references public.profiles(id) on delete cascade,
    -- invitee_id 用 set null（非 cascade）：token 屬於 inviter，被邀請者刪帳號時
    -- 只清掉這一格，不刪整列。詳見 migration 20260701120000。
    invitee_id uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now()
);

-- =====================
-- 5. message_deletions（per-user soft delete）
-- =====================
create table public.message_deletions (
    user_id    uuid not null references public.profiles(id) on delete cascade,
    message_id uuid not null references public.messages(id) on delete cascade,
    deleted_at timestamptz not null default now(),
    primary key (user_id, message_id)
);

-- =====================
-- 6. RLS 開啟
-- =====================
alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.messages enable row level security;
alter table public.invite_tokens enable row level security;
alter table public.message_deletions enable row level security;

-- =====================
-- 7. RLS Policies
-- =====================

-- profiles: 所有人可讀，只能寫自己
create policy "profiles: 任何人可讀"
    on public.profiles for select using (true);

create policy "profiles: 只能更新自己"
    on public.profiles for update using (auth.uid() = id);

-- friendships: 只能看自己相關的
create policy "friendships: 只能看自己的"
    on public.friendships for select
    using (auth.uid() = requester_id or auth.uid() = addressee_id);

create policy "friendships: 只能建立自己發起的"
    on public.friendships for insert
    with check (auth.uid() = requester_id);

create policy "friendships: 只能更新自己相關的"
    on public.friendships for update
    using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- messages: sender/receiver 才能看，body 保護交給 App 層（MVP 先開放讀取 metadata）
-- 排除自己已軟刪除的訊息
create policy "messages: 只能看自己相關的（排除軟刪除）"
    on public.messages for select
    using (
        (auth.uid() = sender_id or auth.uid() = receiver_id)
        and not exists (
            select 1 from public.message_deletions d
            where d.message_id = messages.id
              and d.user_id = auth.uid()
        )
    );

create policy "messages: 只能由 sender 建立"
    on public.messages for insert
    with check (auth.uid() = sender_id);

-- message_deletions: 只能看/新增自己的
create policy "message_deletions: 只能看自己的"
    on public.message_deletions for select
    using (auth.uid() = user_id);

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

-- invite_tokens: 只能看/建立/刪除自己的
create policy "invite_tokens: 只能看自己的"
    on public.invite_tokens for select
    using (auth.uid() = inviter_id);

create policy "invite_tokens: 只能建立自己的"
    on public.invite_tokens for insert
    with check (auth.uid() = inviter_id);

create policy "invite_tokens: 只能刪除自己的"
    on public.invite_tokens for delete
    using (auth.uid() = inviter_id);

-- =====================
-- 8. Functions
-- =====================

-- 產生短邀請碼（格式：DG-XXXXXXXXXX，10位英數大寫，排除易混淆字元 I/O/1/0）
create or replace function generate_short_invite_code()
returns text as $$
declare
    chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result text := 'DG-';
    i int;
begin
    for i in 1..10 loop
        result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    end loop;
    return result;
end;
$$ language plpgsql;

alter table public.invite_tokens
    alter column token set default generate_short_invite_code();

-- check_friend_message_limit: 發訊息前確認 sender 對同一 receiver 的 scheduled 數量未超過 message_limit
create or replace function check_friend_message_limit()
returns trigger as $$
declare
    current_count int;
    sender_limit int;
begin
    select message_limit into sender_limit
    from profiles where id = new.sender_id;

    select count(*) into current_count
    from messages
    where sender_id = new.sender_id
      and receiver_id = new.receiver_id
      and status = 'scheduled'
      and unlock_at > now()
      and not exists (
          select 1 from message_deletions d
          where d.message_id = messages.id
            and d.user_id = new.sender_id
      );

    if current_count >= sender_limit then
        raise exception 'friend_message_limit_exceeded';
    end if;

    return new;
end;
$$ language plpgsql;

create trigger enforce_friend_message_limit
    before insert on public.messages
    for each row execute function check_friend_message_limit();

-- accept_invite: 接受邀請碼，建立好友關係
-- 注意：token 使用後不失效（多次使用設計），invitee_id 只記錄最後一位
create or replace function accept_invite(invite_code text, accepter_id uuid)
returns json as $$
declare
    token_row invite_tokens%rowtype;
begin
    select * into token_row
    from invite_tokens
    where token = invite_code;

    if not found then
        raise exception 'invalid_or_revoked';
    end if;

    if token_row.inviter_id = accepter_id then
        raise exception 'self_invite';
    end if;

    if exists (
        select 1 from friendships
        where (requester_id = token_row.inviter_id and addressee_id = accepter_id)
           or (requester_id = accepter_id and addressee_id = token_row.inviter_id)
    ) then
        raise exception 'already_friends';
    end if;

    insert into friendships (requester_id, addressee_id, status)
    values (token_row.inviter_id, accepter_id, 'accepted');

    update invite_tokens
    set invitee_id = accepter_id
    where id = token_row.id;

    return (
        select json_build_object('id', p.id, 'display_name', p.display_name)
        from profiles p where p.id = token_row.inviter_id
    );
end;
$$ language plpgsql security definer;

-- =====================
-- 9. Data API Grants
-- =====================
-- 讓 Supabase Data API（REST / supabase-js）可以存取這些表格。
-- Supabase 舊版 project 會自動授權，但 2025-10-30 起所有 project 新建的表格
-- 都需要明確 GRANT，否則 API 回傳 permission denied。
-- 各表格只授予實際需要的操作，搭配上方的 RLS policies 使用。

-- profiles: 未登入者也可讀（用於顯示暱稱等公開資訊）
-- INSERT 由 handle_new_user trigger（security definer）處理，不需對 authenticated 開放
grant select on public.profiles to anon, authenticated;
grant update on public.profiles to authenticated;

-- friendships: 只有登入者才能建立 / 查看 / 更新好友關係
grant select, insert, update on public.friendships to authenticated;

-- messages: 只有登入者才能送出 / 查看訊息
grant select, insert on public.messages to authenticated;

-- invite_tokens: 只有登入者才能管理自己的邀請碼
grant select, insert, delete on public.invite_tokens to authenticated;

-- message_deletions: 只有登入者才能查看 / 新增軟刪除記錄
grant select, insert on public.message_deletions to authenticated;
