-- =====================================================================
-- 使用者意見回饋（單向投遞）
--
-- 設計：
--   - insert-only：使用者只能新增自己的回饋，讀不回來（不開 select policy）
--     → 跟 message_deletions 同模式，最單純，沒有 user-keyed cache 要清
--   - category / status 用 check 約束集中管理，未來要加類別／處理狀態直接改這裡
--     （CLAUDE.md：避免散落的 magic string、預留擴充）
--   - 自動帶上的環境欄位（app/os/device/locale/is_premium）由 client 在送出時填
--     → bug 回報沒有這些等於瞎子；使用者不用手動填
--   - email 在 auth.users，可用 user_id join 取得；contact_email 是「想用別的信箱
--     回覆」時才填的選填欄位
-- =====================================================================

create table public.feedback (
    id            uuid primary key default gen_random_uuid(),
    user_id       uuid not null references auth.users(id) on delete cascade,
    category      text check (category in ('bug', 'idea', 'other')),
    content       text not null check (char_length(content) between 1 and 2000),
    contact_email text,
    app_version   text,
    os_version    text,
    device_model  text,
    is_premium    boolean,
    locale        text,
    status        text not null default 'new'
                  check (status in ('new', 'triaged', 'resolved')),
    created_at    timestamptz not null default now()
);

create index feedback_created_at_idx on public.feedback (created_at desc);

alter table public.feedback enable row level security;

-- 只能新增自己的；不開 select／update／delete，使用者投遞後即不可見
create policy "feedback: 只能新增自己的"
    on public.feedback for insert
    with check (auth.uid() = user_id);
