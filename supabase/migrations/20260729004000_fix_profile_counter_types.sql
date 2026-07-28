-- Legacy 0.300 databases may already have these counters as integer.
-- The 0.400 RPC contracts expose them as bigint, so normalize the stored types.
alter table public.profiles
  alter column total_bones type bigint using total_bones::bigint,
  alter column total_piles type bigint using total_piles::bigint;

create or replace function public.get_session_bootstrap()
returns table(
  player_id uuid,display_name text,onboarding_complete boolean,bone_count bigint,
  total_meters bigint,total_bones bigint,total_piles bigint,active_marker_id text,
  home_lat double precision,home_lon double precision,home_changed_at timestamptz,
  walking_mode_enabled boolean,bark_enabled boolean,vibration_enabled boolean,
  is_admin boolean,is_suspended boolean,requires_new_name boolean,created_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  return query select p.id,p.display_name,p.onboarding_complete,p.bone_count,
    p.total_meters,p.total_bones,p.total_piles,p.active_marker_id,
    p.home_lat,p.home_lon,p.home_changed_at,p.walking_mode_enabled,p.bark_enabled,p.vibration_enabled,
    private.is_admin(uid),
    (coalesce(p.suspended_permanently,false) or coalesce(p.suspended_until>now(),false)),
    p.requires_new_name,p.created_at
  from public.profiles p where p.id=uid and p.deleted_at is null;
end $$;
