-- WAVO shared engagement foundation: persistent likes and engagement notifications.
-- Run after wavo_social.sql and wavo_notifications.sql in Supabase SQL Editor.
-- Likes are unique per (video, user); users can only add/remove their own likes.
create table if not exists public.wavo_likes (
  video_name text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (video_name, user_id),
  constraint wavo_likes_video_name_length check (char_length(video_name) between 1 and 500)
);

create index if not exists wavo_likes_user_created_idx
  on public.wavo_likes(user_id, created_at desc);
create index if not exists wavo_likes_video_idx
  on public.wavo_likes(video_name);

alter table public.wavo_likes enable row level security;
drop policy if exists "WAVO likes readable by authenticated users" on public.wavo_likes;
create policy "WAVO likes readable by authenticated users"
  on public.wavo_likes for select to authenticated using (true);
drop policy if exists "WAVO users like as themselves" on public.wavo_likes;
create policy "WAVO users like as themselves"
  on public.wavo_likes for insert to authenticated
  with check (auth.uid() = user_id);
drop policy if exists "WAVO users remove own likes" on public.wavo_likes;
create policy "WAVO users remove own likes"
  on public.wavo_likes for delete to authenticated
  using (auth.uid() = user_id);

grant select, insert, delete on public.wavo_likes to authenticated;

-- Resolve the video owner from the storage path (<auth-user-uuid>/filename).
-- Older root-level uploads intentionally do not generate owner notifications.
create or replace function public.wavo_notify_video_engagement()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_video_name text;
  v_actor uuid;
  v_owner uuid;
  v_kind text;
  v_display text;
begin
  if tg_table_name = 'wavo_comments' then
    v_video_name := new.video_name;
    v_actor := new.user_id;
    v_kind := 'comment';
  else
    v_video_name := new.video_name;
    v_actor := new.user_id;
    v_kind := 'like';
  end if;

  if v_video_name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/' then
    v_owner := split_part(v_video_name, '/', 1)::uuid;
    if v_owner is not null and v_owner <> v_actor then
      v_display := case when v_kind = 'like' then 'أعجب أحد المستخدمين بفيديو لك' else 'علّق أحد المستخدمين على فيديو لك' end;
      insert into public.wavo_notifications(recipient_id, actor_id, type, message, entity_id)
      values (v_owner, v_actor, v_kind, v_display, v_video_name);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists wavo_notify_comment_insert on public.wavo_comments;
create trigger wavo_notify_comment_insert
after insert on public.wavo_comments
for each row execute function public.wavo_notify_video_engagement();

drop trigger if exists wavo_notify_like_insert on public.wavo_likes;
create trigger wavo_notify_like_insert
after insert on public.wavo_likes
for each row execute function public.wavo_notify_video_engagement();

-- Realtime support for likes, if publication exists and the table is not already present.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'wavo_likes'
     ) then
    alter publication supabase_realtime add table public.wavo_likes;
  end if;
end $$;
