-- =====================
-- 1. profiles
-- =====================
create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    username text unique not null,
    display_name text not null,
    message_limit int not null default 1,  -- 每位好友最多可同時 scheduled 的訊息數
    created_at timestamptz not null default now()
);

-- 新用戶註冊時自動建立 profile
create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (id, username, display_name)
    values (
        new.id,
        split_part(new.email, '@', 1),
        split_part(new.email, '@', 1)
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
    invitee_id uuid references public.profiles(id),
    created_at timestamptz not null default now()
);

-- =====================
-- 5. RLS 開啟
-- =====================
alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.messages enable row level security;
alter table public.invite_tokens enable row level security;

-- =====================
-- 6. RLS Policies
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
create policy "messages: 只能看自己相關的"
    on public.messages for select
    using (auth.uid() = sender_id or auth.uid() = receiver_id);

create policy "messages: 只能由 sender 建立"
    on public.messages for insert
    with check (auth.uid() = sender_id);

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
-- 7. Functions
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
      and unlock_at > now();

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
