-- Rəngli Kublar: nailiyyət mükafatlarının TƏHLÜKƏSİZ (server-tərəfli, eyni-vaxtlı cihazlara qarşı
-- qorunmuş) qəbulu üçün. Safe to re-run (uses if not exists / drop policy if exists / create or
-- replace function throughout).
--
-- SƏBƏB: əvvəllər "nailiyyət qəbul edilib" vəziyyəti YALNIZ client-in lokal profilində
-- (profile.claimedAchievements) saxlanılırdı, hər saveProfile() isə BÜTÜN profili (save_data)
-- buludda ÜZƏRİNƏ YAZIRDI (last-write-wins, tam overwrite, heç bir server-tərəfli yoxlama yox).
-- Nəticədə: oyunçu eyni nailiyyəti 2 fərqli cihazda (məs. telefon + kompüter) təxminən eyni vaxtda
-- qəbul edərsə, HƏR İKİ cihaz öz lokal köhnəlmiş halına əsasən "hələ qəbul edilməyib" hesab edib
-- qızılı 2 DƏFƏ verirdi, VƏ "Nailiyyətlər" ekranındakı say ilə liderborddakı say fərqli mənbələrdən
-- gəldiyi üçün uyğunsuz görünürdü.
--
-- HƏLL: nailiyyət qəbulu artıq claim_achievement() funksiyası (SECURITY DEFINER) vasitəsilə,
-- server-tərəfli ATOMIK əməliyyat kimi aparılır. claimed_achievements cədvəlinin (player_id,
-- achievement_id) üzərindəki PRIMARY KEY toqquşması eyni nailiyyətin eyni oyunçu üçün İKİNCİ DƏFƏ
-- uğurla insert olunmasının qarşısını FİZİKİ olaraq alır — hansı cihaz "əvvəl çatsa" o qazanır,
-- digəri false qaytarır və qızıl vermir. profiles.achievements_unlocked sayğacı da BUNDAN sonra
-- YALNIZ bu funksiya tərəfindən (+1 atomik artım) yenilənir, client-in tam overwrite-i ilə YOX —
-- beləliklə bu say heç vaxt həqiqi qəbul sayından ARTIQ ola bilməz.

create table if not exists public.claimed_achievements (
  player_id uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null,
  claimed_at timestamptz not null default now(),
  primary key (player_id, achievement_id)
);

alter table public.claimed_achievements enable row level security;

drop policy if exists "claimed_achievements_select_own" on public.claimed_achievements;
create policy "claimed_achievements_select_own" on public.claimed_achievements
  for select using (auth.uid() = player_id);

drop policy if exists "claimed_achievements_insert_own" on public.claimed_achievements;
create policy "claimed_achievements_insert_own" on public.claimed_achievements
  for insert with check (auth.uid() = player_id);

grant select, insert on public.claimed_achievements to authenticated;

-- Nailiyyəti ATOMIK qəbul edir: bu oyunçu bu nailiyyəti ARTIQ qəbul edibsə (istənilən cihazdan),
-- heç nə etmədən false qaytarır. Əks halda 50 qızıl (ACHIEVEMENT_GOLD_REWARD ilə üst-üstə düşür,
-- server-tərəfli sabit — client-dən gələn məbləğə etibar edilmir) əlavə edir, achievements_unlocked
-- sayğacını atomik artırır və true qaytarır.
create or replace function public.claim_achievement(p_achievement_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  insert into public.claimed_achievements (player_id, achievement_id)
  values (auth.uid(), p_achievement_id)
  on conflict (player_id, achievement_id) do nothing;

  get diagnostics v_rows = row_count;

  if v_rows > 0 then
    update public.profiles
    set gold = gold + 50,
        achievements_unlocked = coalesce(achievements_unlocked, 0) + 1
    where id = auth.uid();
    return true;
  end if;

  return false;
end;
$$;

grant execute on function public.claim_achievement(text) to authenticated;
