-- Rəngli Kublar: profile likes + profile view counter
-- Safe to re-run (uses if not exists / drop policy if exists throughout)

-- ===== Likes =====
alter table public.profiles add column if not exists likes_count integer not null default 0;

create table if not exists public.profile_likes (
  liker_id uuid not null references auth.users(id) on delete cascade,
  liked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (liker_id, liked_id)
);

alter table public.profile_likes enable row level security;

drop policy if exists "profile_likes_select_all" on public.profile_likes;
create policy "profile_likes_select_all" on public.profile_likes
  for select using (true);

drop policy if exists "profile_likes_insert_own" on public.profile_likes;
create policy "profile_likes_insert_own" on public.profile_likes
  for insert with check (auth.uid() = liker_id);

drop policy if exists "profile_likes_delete_own" on public.profile_likes;
create policy "profile_likes_delete_own" on public.profile_likes
  for delete using (auth.uid() = liker_id);

grant select, insert, delete on public.profile_likes to authenticated;
grant select on public.profile_likes to anon;

-- Atomically toggles a like and keeps profiles.likes_count in sync.
-- Returns true if the profile is now liked, false if the like was removed.
create or replace function public.toggle_like(p_target_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_liked boolean;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if auth.uid() = p_target_id then
    raise exception 'cannot like your own profile';
  end if;

  delete from public.profile_likes where liker_id = auth.uid() and liked_id = p_target_id;
  if found then
    update public.profiles set likes_count = greatest(0, likes_count - 1) where id = p_target_id;
    v_liked := false;
  else
    insert into public.profile_likes (liker_id, liked_id) values (auth.uid(), p_target_id);
    update public.profiles set likes_count = likes_count + 1 where id = p_target_id;
    v_liked := true;
  end if;

  return v_liked;
end;
$$;

grant execute on function public.toggle_like(uuid) to authenticated;

-- ===== Profile view counter =====
alter table public.profiles add column if not exists view_count integer not null default 0;

-- Increments the target's view_count. No-ops (does nothing, no error) if viewing your own profile.
create or replace function public.increment_profile_view(p_target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or auth.uid() = p_target_id then
    return;
  end if;
  update public.profiles set view_count = view_count + 1 where id = p_target_id;
end;
$$;

grant execute on function public.increment_profile_view(uuid) to authenticated;
