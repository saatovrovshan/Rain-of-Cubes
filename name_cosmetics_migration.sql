-- Rəngli Kublar: denormalized columns so other players can see a player's
-- active name color/animation (same pattern as active_frame). No RLS/GRANT
-- changes needed — covered by the existing owner-update / public-select
-- policies already in place on profiles.

alter table public.profiles add column if not exists active_name_color text;
alter table public.profiles add column if not exists active_name_anim text;
