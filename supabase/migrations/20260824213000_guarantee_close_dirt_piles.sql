-- Dense bones must not crowd dirt piles out of populated areas.
-- Keep icons from landing exactly on top of each other, but only require
-- about 10 m from a loose bone.
do $$ declare d text; begin
  d:=pg_get_functiondef('private.maintain_dirt_piles(double precision,double precision)'::regprocedure);
  d:=replace(d,'< 100','< 10');d:=replace(d,'<100','<10');
  d:=replace(d,'< 45','< 10');d:=replace(d,'<45','<10');
  execute d;
end $$;

create or replace function private.ensure_close_dirt_pile(player_lat double precision,player_lon double precision)
returns void language plpgsql volatile security definer set search_path='' as $$
declare candidate record;t smallint;
begin
  if exists(
    select 1 from public.dirt_piles d where d.active
      and private.distance_meters(player_lat,player_lon,d.latitude,d.longitude)<=350
  ) then return;end if;

  select w.latitude,w.longitude into candidate
  from private.walkable_spawn_candidates w
  where w.latitude between player_lat-.0036 and player_lat+.0036
    and w.longitude between player_lon-(.0036/greatest(.15,cos(radians(player_lat))))
                        and player_lon+(.0036/greatest(.15,cos(radians(player_lat))))
    and private.distance_meters(player_lat,player_lon,w.latitude,w.longitude) between 80 and 350
    and not exists(select 1 from public.dirt_piles d where d.active
      and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<250)
    and not exists(select 1 from public.world_bones b where b.active
      and b.latitude between w.latitude-.0005 and w.latitude+.0005
      and b.longitude between w.longitude-.001 and w.longitude+.001
      and private.distance_meters(w.latitude,w.longitude,b.latitude,b.longitude)<10)
  order by private.distance_meters(player_lat,player_lon,w.latitude,w.longitude),random()
  limit 1;
  if found then
    t:=floor(random()*5)::smallint;
    insert into public.dirt_piles(latitude,longitude,pile_type,cost,active,placement_source,updated_at)
    values(candidate.latitude,candidate.longitude,t,(array[10,25,50,100,250])[t+1],true,'system',now());
  end if;
end $$;
revoke all on function private.ensure_close_dirt_pile(double precision,double precision) from public,anon,authenticated;

create or replace function public.refresh_world_nearby(p_latitude double precision,p_longitude double precision)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();begin
  if uid is null then raise exception 'AUTH_REQUIRED';end if;
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then raise exception 'GPS_REQUIRED';end if;
  perform set_config('statement_timeout','12s',true);
  perform private.maintain_world_bones(p_latitude,p_longitude);
  perform private.maintain_dirt_piles(p_latitude,p_longitude);
  perform private.ensure_close_dirt_pile(p_latitude,p_longitude);
  return jsonb_build_object('ok',true,'radius_m',2000,'bone_spacing_m',100,'pile_spacing_m',250,'close_pile_m',350);
end $$;
revoke execute on function public.refresh_world_nearby(double precision,double precision) from public,anon;
grant execute on function public.refresh_world_nearby(double precision,double precision) to authenticated;

-- Apply the close-pile guarantee immediately for recently active areas.
do $$ declare p record;begin
  for p in select distinct on(round(latitude::numeric,3),round(longitude::numeric,3)) latitude,longitude
    from public.player_presence where updated_at>=now()-interval '7 days' and accuracy_m<=75
    order by round(latitude::numeric,3),round(longitude::numeric,3),updated_at desc
  loop perform private.ensure_close_dirt_pile(p.latitude,p.longitude);end loop;
end $$;
notify pgrst,'reload schema';
