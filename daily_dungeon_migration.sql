-- Gündəlik Zindan (Daily Dungeon) — TEST mərhələsi üçün hazırlanıb, HƏLƏ İŞƏ SALINMAYIB.
-- Yalnız bu, canlı liderbordu (digər oyunçuların skorlarını görmək) aktivləşdirir — özün üçün
-- lokal test (profile.dungeonScores) bu migrasiya olmadan da tam işləyir.
-- Safe to re-run (hamısı "if not exists" / "drop policy if exists" ilədir).
--
-- Hər user_id+date üçün BİR sətir var (gündə maksimum 3 oyun hüququ ilə uyğun) —
-- total_score = bugünkü 3 oyunun xallarının CƏMİ ("Günün Lideri" liderbordu bunu istifadə edir)
-- best_score  = bugünkü 3 oyundan ƏN YÜKSƏK tək xal ("Zindan Lideri" liderbordu bunu istifadə edir)
-- games_played = bugün neçə oyun oynanıb (0-3) — klient tərəfdə gündəlik limiti tətbiq etmək üçün

create table if not exists daily_dungeon_scores (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  date text not null,
  total_score int not null default 0,
  best_score int not null default 0,
  games_played int not null default 0,
  name text,
  level int default 1,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(user_id, date)
);

alter table daily_dungeon_scores enable row level security;

drop policy if exists "Insert own score" on daily_dungeon_scores;
create policy "Insert own score" on daily_dungeon_scores
  for insert with check (auth.uid() = user_id);

-- upsert-in ÜZƏRİNƏ YAZMA (conflict) yolu üçün lazımdır — RLS-də yalnız INSERT policy
-- olsa, eyni günə İKİNCİ (və 3-cü) dəfə upsert cəhdi UPDATE mərhələsində səssizcə rədd edilir.
drop policy if exists "Update own score" on daily_dungeon_scores;
create policy "Update own score" on daily_dungeon_scores
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Read all daily scores" on daily_dungeon_scores;
create policy "Read all daily scores" on daily_dungeon_scores
  for select using (true);

grant select, insert, update on daily_dungeon_scores to authenticated;
grant select on daily_dungeon_scores to anon;
