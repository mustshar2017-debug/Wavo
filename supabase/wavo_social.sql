-- WAVO social foundation: public profiles and follow relationships
create table if not exists public.wavo_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'WAVO user',
  avatar_url text,
  updated_at timestamptz not null default now()
);

create table if not exists public.wavo_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint wavo_no_self_follow check (follower_id <> following_id)
);

alter table public.wavo_profiles enable row level security;
alter table public.wavo_follows enable row level security;

drop policy if exists "WAVO profiles readable by authenticated users" on public.wavo_profiles;
create policy "WAVO profiles readable by authenticated users"
on public.wavo_profiles for select to authenticated using (true);

drop policy if exists "WAVO users insert own profile" on public.wavo_profiles;
create policy "WAVO users insert own profile"
on public.wavo_profiles for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "WAVO users update own profile" on public.wavo_profiles;
create policy "WAVO users update own profile"
on public.wavo_profiles for update to authenticated
using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "WAVO follows readable by authenticated users" on public.wavo_follows;
create policy "WAVO follows readable by authenticated users"
on public.wavo_follows for select to authenticated using (true);

drop policy if exists "WAVO users follow as themselves" on public.wavo_follows;
create policy "WAVO users follow as themselves"
on public.wavo_follows for insert to authenticated with check (auth.uid() = follower_id and follower_id <> following_id);

drop policy if exists "WAVO users unfollow as themselves" on public.wavo_follows;
create policy "WAVO users unfollow as themselves"
on public.wavo_follows for delete to authenticated using (auth.uid() = follower_id);

create index if not exists wavo_follows_following_idx on public.wavo_follows(following_id);
create index if not exists wavo_follows_follower_idx on public.wavo_follows(follower_id);


-- WAVO shared video comments
create table if not exists public.wavo_comments (
  id uuid primary key default gen_random_uuid(),
  video_name text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default 'WAVO user',
  body text not null check (char_length(body) between 1 and 300),
  created_at timestamptz not null default now()
);
alter table public.wavo_comments enable row level security;
drop policy if exists "WAVO comments readable by authenticated users" on public.wavo_comments;
create policy "WAVO comments readable by authenticated users"
on public.wavo_comments for select to authenticated using (true);
drop policy if exists "WAVO users add comments as themselves" on public.wavo_comments;
create policy "WAVO users add comments as themselves"
on public.wavo_comments for insert to authenticated with check (auth.uid() = user_id);
create index if not exists wavo_comments_video_created_idx
on public.wavo_comments(video_name, created_at);
