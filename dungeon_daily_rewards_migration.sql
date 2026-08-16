-- Gündəlik Zindan reytinq mükafatları (TEST — hələ əsas oyuna əlavə olunmayıb, index_dungeon_test.html-də)
-- Hər gün bitəndə (client-side, server cron olmadığı üçün leaderboard_rank_changes-dəki EYNİ
-- prinsiplə) DÜNƏNKİ günün 2 liderbordunun (Günün Lideri = total_score, Zindan Lideri = best_score)
-- sıralamasına görə hər oyunçu üçün BİR sətir yazılır — sonra "Mesajlar" tabında "Zindan" sistem
-- göndəricisinin məktubları kimi göstərilir, "Mükafatları al" düyməsi ilə qəbul edilir (claimed=false -> true).
-- created_at məktubun tam tarix+saatını göstərmək üçün istifadə olunur.
-- Safe to re-run (if not exists / drop policy if exists).

create table if not exists dungeon_daily_rewards (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  date text not null,
  category text not null,           -- 'daily' (Günün Lideri) və ya 'best' (Zindan Lideri)
  rank int not null,
  score int not null default 0,
  games_played int not null default 0,
  gold int not null default 0,
  cubes_per_color int not null default 0,
  color_ids jsonb not null default '[]'::jsonb,  -- həmin günün zindanında olan rənglərin id-ləri
  claimed boolean not null default false,
  created_at timestamptz default now(),
  unique(user_id, date, category)
);

alter table dungeon_daily_rewards enable row level security;

drop policy if exists "Select own dungeon rewards" on dungeon_daily_rewards;
create policy "Select own dungeon rewards" on dungeon_daily_rewards
  for select using (auth.uid() = user_id);

-- Hər hansı giriş etmiş oyunçu, gün dəyişəndə DİGƏR bütün iştirakçılar üçün də mükafat
-- sətirlərini hesablayıb yaza bilsin (bax finalizeDungeonRewardsForDate) — leaderboard_rank_changes-in
-- "insert any authed" policy-si ilə EYNİ məntiq.
drop policy if exists "Insert dungeon rewards any authed" on dungeon_daily_rewards;
create policy "Insert dungeon rewards any authed" on dungeon_daily_rewards
  for insert with check (auth.uid() is not null);

-- Yalnız öz sətrini (claimed=true etmək üçün) yeniləyə bilsin
drop policy if exists "Update own dungeon rewards" on dungeon_daily_rewards;
create policy "Update own dungeon rewards" on dungeon_daily_rewards
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update on dungeon_daily_rewards to authenticated;
