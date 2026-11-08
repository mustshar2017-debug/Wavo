-- WAVO private messages: run this entire file in Supabase SQL Editor.
-- Each message is visible only to its sender and recipient.
create table if not exists public.wavo_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint wavo_messages_no_self_message check (sender_id <> recipient_id)
);

create index if not exists wavo_messages_sender_created_idx
  on public.wavo_messages (sender_id, created_at desc);
create index if not exists wavo_messages_recipient_created_idx
  on public.wavo_messages (recipient_id, created_at desc);

alter table public.wavo_messages enable row level security;

drop policy if exists "wavo_messages_select_participant" on public.wavo_messages;
create policy "wavo_messages_select_participant"
on public.wavo_messages for select to authenticated
using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists "wavo_messages_insert_sender" on public.wavo_messages;
create policy "wavo_messages_insert_sender"
on public.wavo_messages for insert to authenticated
with check (auth.uid() = sender_id and auth.uid() <> recipient_id
  and char_length(body) between 1 and 2000);

drop policy if exists "wavo_messages_recipient_marks_read" on public.wavo_messages;
create policy "wavo_messages_recipient_marks_read"
on public.wavo_messages for update to authenticated
using (auth.uid() = recipient_id)
with check (auth.uid() = recipient_id);

grant select, insert, update on public.wavo_messages to authenticated;

-- Enable Realtime for new-message notifications if it is not already enabled.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'wavo_messages'
  ) then
    alter publication supabase_realtime add table public.wavo_messages;
  end if;
end $$;
