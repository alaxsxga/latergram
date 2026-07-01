-- =====================================================================
-- invite_tokens.invitee_id 外鍵改成 ON DELETE SET NULL
--
-- 動機（刪除帳號功能 / Apple Guideline 5.1.1(v)）：
--   刪除帳號時走 auth.admin.deleteUser(id)，靠外鍵 cascade 清掉該用戶
--   散在各表的資料。除了 invitee_id 以外，所有指向該用戶的外鍵都是
--   ON DELETE CASCADE：
--     profiles.id → auth.users            cascade
--     friendships / messages / invite_tokens.inviter_id
--       / message_deletions / processed_transactions → profiles  cascade
--     feedback.user_id → auth.users       cascade
--
--   唯獨 invite_tokens.invitee_id → profiles(id) 建表時沒指定 ON DELETE，
--   預設是 NO ACTION。而 accept_invite() 會把「接受邀請的人」寫進對方
--   token 的 invitee_id，所以只要該用戶曾接受過任何邀請，刪除時就會撞這條
--   外鍵 → 整筆刪除失敗。
--
--   這一列（token）屬於「邀請人」，不該因被邀請者退出而消失，所以不能
--   cascade 刪整列，只把 invitee_id 清成 null（token 保留、多人可用設計
--   不受影響）。
-- =====================================================================

alter table public.invite_tokens
    drop constraint invite_tokens_invitee_id_fkey,
    add constraint invite_tokens_invitee_id_fkey
        foreign key (invitee_id) references public.profiles(id) on delete set null;
