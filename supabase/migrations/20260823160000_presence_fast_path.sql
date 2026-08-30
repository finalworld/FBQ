-- GPS presence is a latency-critical write. World maintenance used to run in
-- this transaction and could hit statement_timeout, making players disappear
-- and causing every physical action that refreshed presence to fail.
create or replace function public.update_presence(
  latitude double precision,longitude double precision,accuracy_m real,
  heading real default 0,speed_mps real default null,is_background boolean default false
) returns timestamptz language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid();stamp timestamptz:=clock_timestamp();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  perform private.assert_active_player(uid);
  if latitude not between -90 and 90 or longitude not between -180 and 180 or accuracy_m<=0 or accuracy_m>10000 then
    raise exception 'INVALID_LOCATION' using errcode='22023';
  end if;
  insert into public.player_presence(player_id,latitude,longitude,accuracy_m,heading,speed_mps,is_background,moved_at,updated_at)
  values(uid,latitude,longitude,accuracy_m,coalesce(heading,0),speed_mps,is_background,stamp,stamp)
  on conflict(player_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,
    accuracy_m=excluded.accuracy_m,heading=excluded.heading,speed_mps=excluded.speed_mps,
    is_background=excluded.is_background,moved_at=case when private.distance_meters(
      public.player_presence.latitude,public.player_presence.longitude,excluded.latitude,excluded.longitude)>2
      then stamp else public.player_presence.moved_at end,updated_at=stamp;
  return stamp;
end $$;

revoke execute on function public.update_presence(double precision,double precision,real,real,real,boolean) from public,anon;
grant execute on function public.update_presence(double precision,double precision,real,real,real,boolean) to authenticated;
