-- Rəngli Kublar: nailiyyət sistemi üçün 2 AYRI server-tərəfli qorunma. Safe to re-run (uses if
-- not exists / drop policy if exists / create or replace function throughout).
--
-- SƏBƏB: əvvəllər həm "qəbul edilib" (claimedAchievements) HƏM DƏ "açılıb" (unlockedAchievements)
-- vəziyyəti YALNIZ client-in lokal profilində saxlanılırdı, hər saveProfile() isə BÜTÜN profili
-- (save_data, o cümlədən köhnə achievements_unlocked sütunu) buludda ÜZƏRİNƏ YAZIRDI (last-write-
-- wins, tam overwrite, server-tərəfli yoxlama yox). Bunun İKİ AYRI NƏTİCƏSİ var idi:
--   1) Oyunçu eyni nailiyyəti 2 fərqli cihazda (məs. telefon + kompüter) təxminən eyni vaxtda qəbul
--      etsə, HƏR İKİ cihaz "hələ qəbul edilməyib" hesab edib qızılı 2 DƏFƏ verirdi.
--   2) "Nailiyyətlər" ekranındakı say (neçə nailiyyət AÇILIB) ilə liderborddakı say fərqli
--      cihazların köhnəlmiş overwrite-lərinə görə uyğunsuz qala bilirdi.
--
-- DİQQƏT: "açılmış" (unlocked) və "qəbul edilmiş" (claimed) İKİ FƏRQLİ ŞEYDİR — oyunçu bir
-- nailiyyəti AÇA bilər, mükafatını isə HƏLƏ QƏBUL ETMƏYƏ bilər. "Nailiyyətlər" ekranı AÇILMIŞ
-- sayını göstərir, ona görə liderbord da HƏMİN sayı göstərməlidir ki, iki ədəd HƏMİŞƏ üst-üstə
-- düşsün (əks halda, "qəbul edilmiş" sayı "açılmış" sayından HEÇ VAXT çox ola bilməz, amma fərqli
-- ola bilər, bu da "110 açılıb, niyə liderbordda 111 var" kimi qarışıqlıq yaradır).
--
-- HƏLL: 2 ayrı, ATOMIK mexanizm:
--   A) claim_achievement() — qızılın 2 dəfə verilməsinin qarşısını alır (claimed_achievements)
--   B) sync_unlocked_achievements() — "Nailiyyətlər" ekranındakı AÇILMIŞ sayını buludda dəqiq və
--      HEÇ VAXT azalmayan şəkildə saxlayır (unlocked_achievements), achievements_unlocked bundan
--      sonra YALNIZ bu funksiya tərəfindən yenilənir, client-in tam overwrite-i ilə YOX.

-- ===== A) Qızılın 2 dəfə verilməsinin qarşısını alan hissə =====

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
-- server-tərəfli sabit — client-dən gələn məbləğə etibar edilmir) əlavə edir və true qaytarır.
-- DİQQƏT: achievements_unlocked-a TOXUNMUR — o, aşağıdakı sync_unlocked_achievements()-in işidir.
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
    update public.profiles set gold = gold + 50 where id = auth.uid();
    return true;
  end if;

  return false;
end;
$$;

grant execute on function public.claim_achievement(text) to authenticated;

-- ===== B) "Nailiyyətlər" ekranındakı AÇILMIŞ sayının liderbordla üst-üstə düşməsini təmin edən hissə =====

create table if not exists public.unlocked_achievements (
  player_id uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null,
  unlocked_at timestamptz not null default now(),
  primary key (player_id, achievement_id)
);

alter table public.unlocked_achievements enable row level security;

drop policy if exists "unlocked_achievements_select_own" on public.unlocked_achievements;
create policy "unlocked_achievements_select_own" on public.unlocked_achievements
  for select using (auth.uid() = player_id);

drop policy if exists "unlocked_achievements_insert_own" on public.unlocked_achievements;
create policy "unlocked_achievements_insert_own" on public.unlocked_achievements
  for insert with check (auth.uid() = player_id);

grant select, insert on public.unlocked_achievements to authenticated;

-- Client hər dəfə YENİ nailiyyət(lər) aça bilən yoxlama apardıqda, HAZIRKI bildiyi bütün açılmış
-- ID-lərin siyahısını göndərir. ON CONFLICT DO NOTHING sayəsində təkrarlar problem yaratmır (başqa
-- cihazdan artıq qeyd olunmuş ID-lər sakitcə keçilir). Sondan profiles.achievements_unlocked HƏMİŞƏ
-- unlocked_achievements-in HƏQİQİ sətir sayına (count(*)) bərabərlənir — beləliklə bu say HEÇ VAXT
-- azalmır (yalnız yeni, HƏQİQİ açılışlarla artır) və HEÇ VAXT "Nailiyyətlər" ekranındakı AÇILMIŞ
-- sayından fərqli ola bilməz.
create or replace function public.sync_unlocked_achievements(p_achievement_ids text[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  insert into public.unlocked_achievements (player_id, achievement_id)
  select auth.uid(), unnest(p_achievement_ids)
  on conflict (player_id, achievement_id) do nothing;

  select count(*) into v_count from public.unlocked_achievements where player_id = auth.uid();

  update public.profiles set achievements_unlocked = v_count where id = auth.uid();

  return v_count;
end;
$$;

grant execute on function public.sync_unlocked_achievements(text[]) to authenticated;

-- ============================================================================
-- BİR DƏFƏLİK DÜZƏLİŞ (İSTƏYƏ BAĞLI, amma tövsiyə olunur) — yalnız YUXARIDAKI hissələri işə
-- saldıqdan SONRA, BİR DƏFƏ işə sal. Yuxarıdakı hissələr YALNIZ BUNDAN SONRAKI hərəkətləri qoruyur.
-- Bu blok hər oyunçunun save_data-dakı HƏQİQİ AÇILMIŞ nailiyyətlərini unlocked_achievements
-- cədvəlinə köçürür və achievements_unlocked-ı bu HƏQİQİ sayla üst-üstə salır — nəticədə
-- "Nailiyyətlər" ekranı ilə liderbord dərhal EYNİ rəqəmi göstərəcək. Təhlükəsizdir, bir neçə dəfə
-- işə salsan belə eyni nəticəni verir.
-- save_data ola bilsin json (jsonb yox) tipində saxlanılır, YA DA bəzi sətirlərdə
-- unlockedAchievements açarı obyekt olmaya bilər (null, array və s.) — hər ikisini ehtiyatla
-- ::jsonb-ə çeviririk və CASE ilə YALNIZ həqiqi obyekt olanda jsonb_object_keys çağırırıq, əks
-- halda boş obyektə keçirik ki, FROM-dakı funksiya heç vaxt uyğunsuz dəyərlə çağırılıb sıradan
-- çıxmasın (nəticədə həmin sətir üçün sadəcə heç bir açar qaytarılmır, xəta yaranmır)
insert into public.unlocked_achievements (player_id, achievement_id, unlocked_at)
select p.id, key, now()
from public.profiles p,
  jsonb_object_keys(
    case when jsonb_typeof(p.save_data::jsonb->'unlockedAchievements') = 'object'
         then p.save_data::jsonb->'unlockedAchievements'
         else '{}'::jsonb
    end
  ) as key
on conflict (player_id, achievement_id) do nothing;

update public.profiles p
set achievements_unlocked = (
  select count(*) from public.unlocked_achievements u where u.player_id = p.id
);

-- Yoxlama: bu sorğu hər oyunçu üçün save_data-nın strukturunu göstərir — əgər unlocked_type
-- sütunu "object" DEYİLSƏ (məs. "null" və ya boşdursa), demək o oyunçunun save_data-sında
-- unlockedAchievements HEÇ YOXDUR və ya fərqli formatdadır, backfill onun üçün heç nə etməyəcək
-- (bu, YENİ nailiyyət açanda sync_unlocked_achievements() ilə özü-özünə düzələcək)
select id, name, achievements_unlocked,
  jsonb_typeof(save_data::jsonb->'unlockedAchievements') as unlocked_type,
  (select count(*) from public.unlocked_achievements u where u.player_id = profiles.id) as unlocked_rows_now
from public.profiles
order by achievements_unlocked desc nulls last
limit 15;
-- ============================================================================
