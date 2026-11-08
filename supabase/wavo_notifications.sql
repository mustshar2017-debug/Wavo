-- WAVO notifications: follow + private message events
create table if not exists public.wavo_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  type text not null check (type in ('follow','message','like','comment')),
  message text,
  entity_id text,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists wavo_notifications_recipient_created_idx
  on public.wavo_notifications (recipient_id, created_at desc);
create index if not exists wavo_notifications_unread_idx
  on public.wavo_notifications (recipient_id) where read_at is null;

alter table public.wavo_notifications enable row level security;
drop policy if exists "Users read own notifications" on public.wavo_notifications;
create policy "Users read own notifications" on public.wavo_notifications
  for select to authenticated using (auth.uid() = recipient_id);
drop policy if exists "Users mark own notifications read" on public.wavo_notifications;
create policy "Users mark own notifications read" on public.wavo_notifications
  for update to authenticated using (auth.uid() = recipient_id)
  with check (auth.uid() = recipient_id);
revoke insert, delete on public.wavo_notifications from anon, authenticated;
grant select on public.wavo_notifications to authenticated;
grant update (read_at) on public.wavo_notifications to authenticated;

create or replace function public.wavo_notify_new_follow()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.follower_id is distinct from new.following_id then
    insert into public.wavo_notifications(recipient_id, actor_id, type, entity_id)
    values (new.following_id, new.follower_id, 'follow', new.follower_id::text);
  end if;
  return new;
end;
$$;
drop trigger if exists wavo_notify_follow_insert on public.wavo_follows;
create trigger wavo_notify_follow_insert
after insert on public.wavo_follows
for each row execute function public.wavo_notify_new_follow();

create or replace function public.wavo_notify_new_message()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.wavo_notifications(recipient_id, actor_id, type, entity_id)
  values (new.recipient_id, new.sender_id, 'message', new.id::text);
  return new;
end;
$$;
drop trigger if exists wavo_notify_message_insert on public.wavo_messages;
create trigger wavo_notify_message_insert
after insert on public.wavo_messages
for each row execute function public.wavo_notify_new_message();

-- Like/comment notification types are prepared, but those interactions currently
-- live in browser local storage and cannot generate cross-account notifications yet.
