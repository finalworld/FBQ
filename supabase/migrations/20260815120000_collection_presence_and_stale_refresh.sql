-- Keep collection validation and world refresh on the same usable GPS range.
-- Collection accepts fixes up to 75 m, so maintenance must not stop at 30 m
-- and leave expired map objects stuck on "snart" indefinitely.

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

  if accuracy_m<=75 then
    perform private.maintain_world_bones(latitude,longitude);
    perform private.maintain_dirt_piles(latitude,longitude);
  end if;
  return stamp;
end $$;

revoke execute on function public.update_presence(double precision,double precision,real,real,real,boolean) from public,anon;
grant execute on function public.update_presence(double precision,double precision,real,real,real,boolean) to authenticated;

-- Refresh stale objects immediately around players who have recently played.
do $$
declare p record;
begin
  for p in
    select latitude,longitude from public.player_presence
    where updated_at>now()-interval '24 hours' and accuracy_m<=75
    order by updated_at desc
  loop
    perform private.maintain_world_bones(p.latitude,p.longitude);
    perform private.maintain_dirt_piles(p.latitude,p.longitude);
  end loop;
end $$;
