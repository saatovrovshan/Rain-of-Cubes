-- Rəngli Kublar: liderbord sıra hərəkəti göstəriciləri (+N / -N, gündəlik)
-- Safe to re-run (uses if not exists / drop policy if exists throughout)
--
-- Server-side cron olmadığı üçün gündəlik "sıra snapshot"u KLIENT tərəfindən tətbiq olunur:
-- hər hansı bir oyunçu liderbordu açanda, həmin kateqoriyada gördüyü oyunçular üçün əvvəlki
-- saxlanılmış sıra ilə bugünkü sıranı müqayisə edir. Müqayisə gün ərzində YALNIZ BİR DƏFƏ
-- edilir (computed_date bugünlə üst-üstə düşməyəndə) — beləliklə göstərilən +/- dəyəri həmin
-- gün ərzində sabit qalır, hər dəfə liderbord açılanda yenidən hesablanmır.

create table if not exists public.leaderboard_rank_changes (
  category text not null,
  player_id uuid not null references auth.users(id) on delete cascade,
  current_rank integer not null,
  rank_change integer not null default 0,
  computed_date date not null,
  primary key (category, player_id)
);

alter table public.leaderboard_rank_changes enable row level security;

drop policy if exists "lb_rank_changes_select_all" on public.leaderboard_rank_changes;
create policy "lb_rank_changes_select_all" on public.leaderboard_rank_changes
  for select using (true);

-- Hər hansı giriş etmiş oyunçu gündəlik snapshotu yeniləyə bilsin (kim əvvəl liderbordu
-- açsa, həmin gün üçün digər görünən oyunçuların da sırasını o hesablayıb saxlayır)
drop policy if exists "lb_rank_changes_insert_any_authed" on public.leaderboard_rank_changes;
create policy "lb_rank_changes_insert_any_authed" on public.leaderboard_rank_changes
  for insert with check (auth.uid() is not null);

drop policy if exists "lb_rank_changes_update_any_authed" on public.leaderboard_rank_changes;
create policy "lb_rank_changes_update_any_authed" on public.leaderboard_rank_changes
  for update using (auth.uid() is not null);

-- RLS policy-ləri təkbaşına kifayət deyil — sətir səviyyəsində icazə versələr də, əgər rol
-- cədvələ əsas GRANT-a malik deyilsə (aşağıdakılar bu faylda ƏSKİK idi), sorğu "permission
-- denied for table" (42501) xətası ilə uğursuz olur və liderborddakı bütün +/- göstəriciləri
-- səssizcə heç vaxt görünmür (bax computeRankChanges-in catch bloku).
grant select, insert, update on public.leaderboard_rank_changes to authenticated;
grant select on public.leaderboard_rank_changes to anon;
