-- WAVO LIVE: database tables and row-level security
-- Run this file in the Supabase SQL Editor for project jajaujilwhkroboyhenj.

create table if not exists public.wavo_live_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.wavo_live_sessions (
  id uuid primary key default gen_random_uuid(),
  room_name text not null unique,
  host_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'بث مباشر',
  status text not null default 'live' check (status in ('live', 'ended')),
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

create index if not exists wavo_live_sessions_status_started_idx
  on public.wavo_live_sessions (status, started_at desc);
create index if not exists wavo_live_sessions_host_status_idx
  on public.wavo_live_sessions (host_user_id, status);

create table if not exists public.wavo_live_chat (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.wavo_live_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(message) between 1 and 500),
  created_at timestamptz not null default now()
);

create index if not exists wavo_live_chat_session_created_idx
  on public.wavo_live_chat (session_id, created_at);

alter table public.wavo_live_admins enable row level security;
alter table public.wavo_live_sessions enable row level security;
alter table public.wavo_live_chat enable row level security;

-- Admin membership is managed only by the project owner/service role.
drop policy if exists "live sessions readable by signed-in users" on public.wavo_live_sessions;
drop policy if exists "live sessions publicly readable" on public.wavo_live_sessions;
create policy "live sessions publicly readable"
  on public.wavo_live_sessions for select to anon, authenticated
  using (true);

drop policy if exists "live chat readable by signed-in users" on public.wavo_live_chat;
create policy "live chat readable by signed-in users"
  on public.wavo_live_chat for select to authenticated
  using (true);

drop policy if exists "signed-in users can chat in live sessions" on public.wavo_live_chat;
create policy "signed-in users can chat in live sessions"
  on public.wavo_live_chat for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.wavo_live_sessions s
      where s.id = session_id and s.status = 'live'
    )
  );

grant select on public.wavo_live_sessions to anon, authenticated;
grant select, insert on public.wavo_live_chat to authenticated;
