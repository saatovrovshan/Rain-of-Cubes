-- Rəngli Kublar: gift hide/delete management (own profile gift list)
-- Safe to re-run

alter table public.gifts add column if not exists hidden boolean not null default false;
alter table public.gifts add column if not exists deleted boolean not null default false;

-- Receiver can update their own received gift rows (used for marking seen, hidden, deleted).
-- If this policy already exists from an earlier migration, this redefines it identically.
drop policy if exists "gifts_update_receiver" on public.gifts;
create policy "gifts_update_receiver" on public.gifts
  for update using (auth.uid() = to_user) with check (auth.uid() = to_user);

grant update on public.gifts to authenticated;
