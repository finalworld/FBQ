-- Stability fix 2: faster set-based world maintenance and more worthwhile finds.
update public.bone_types b set spawn_weight=v.spawn_weight
from (values
  (0::smallint,1700),(1::smallint,1900),(2::smallint,1700),(3::smallint,1500),
  (4::smallint,1100),(5::smallint,800),(6::smallint,500),(7::smallint,350),
  (8::smallint,220),(9::smallint,130),(10::smallint,70),(11::smallint,30)
) v(id,spawn_weight) where b.id=v.id;

create or replace function private.maintain_world_bones(player_lat double precision,player_lon double precision)
returns void language plpgsql volatile security definer set search_path='' as $$
declare nearby_count integer;needed integer;
begin
  if not pg_try_advisory_xact_lock(1179666257) then return;end if;
  update public.world_bones set bone_type=private.random_bone_type(),generation=generation+1,updated_at=now()
  where active and placement_source='system' and updated_at<=now()-interval '5 hours';
  update public.world_bones set bone_type=private.random_bone_type(),active=true,respawn_at=null,
    collected_at=null,generation=generation+1,updated_at=now()
  where not active and placement_source='system' and respawn_at<=now();
  perform private.ensure_close_bones(player_lat,player_lon);
  select count(*) into nearby_count from public.world_bones b
  where b.active and b.placement_source='system'
    and b.latitude between player_lat-.0185 and player_lat+.0185
    and b.longitude between player_lon-(.0185/greatest(.15,cos(radians(player_lat)))) and player_lon+(.0185/greatest(.15,cos(radians(player_lat))))
    and private.distance_meters(player_lat,player_lon,b.latitude,b.longitude)<=2000;
  needed:=greatest(0,170-nearby_count);if needed=0 then return;end if;
  insert into public.world_bones(latitude,longitude,bone_type,active,placement_source,updated_at)
  select q.latitude,q.longitude,private.random_bone_type(),true,'system',now() from (
    select c.latitude,c.longitude,row_number() over(partition by floor(c.latitude*1113.2),floor(c.longitude*1113.2*greatest(.15,cos(radians(player_lat)))) order by random()) grid_pick
    from private.walkable_spawn_candidates c
    where c.latitude between player_lat-.0185 and player_lat+.0185
      and c.longitude between player_lon-(.0185/greatest(.15,cos(radians(player_lat)))) and player_lon+(.0185/greatest(.15,cos(radians(player_lat))))
      and private.distance_meters(player_lat,player_lon,c.latitude,c.longitude)<=2000
      and not exists(select 1 from public.world_bones b where b.active and b.latitude between c.latitude-.001 and c.latitude+.001 and b.longitude between c.longitude-.002 and c.longitude+.002 and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<100)
      and not exists(select 1 from public.dirt_piles d where d.active and d.latitude between c.latitude-.0002 and c.latitude+.0002 and d.longitude between c.longitude-.0003 and c.longitude+.0003 and private.distance_meters(c.latitude,c.longitude,d.latitude,d.longitude)<10)
  ) q where q.grid_pick=1 order by random() limit needed;
end $$;
revoke all on function private.maintain_world_bones(double precision,double precision) from public,anon,authenticated;

create or replace function private.maintain_dirt_piles(player_lat double precision,player_lon double precision)
returns void language plpgsql volatile security definer set search_path='' as $$
declare n integer;needed integer;
begin
  with due as (select id,floor(random()*5)::smallint t from public.dirt_piles where not active and respawn_at<=now() for update skip locked)
  update public.dirt_piles d set pile_type=due.t,cost=(array[10,25,50,100,250])[due.t+1],active=true,respawn_at=null,claimed_at=null,generation=d.generation+1,updated_at=now() from due where d.id=due.id;
  select count(*) into n from public.dirt_piles d where d.active
    and d.latitude between player_lat-.0185 and player_lat+.0185
    and d.longitude between player_lon-(.0185/greatest(.15,cos(radians(player_lat)))) and player_lon+(.0185/greatest(.15,cos(radians(player_lat))))
    and private.distance_meters(player_lat,player_lon,d.latitude,d.longitude)<=2000;
  needed:=greatest(0,30-n);if needed=0 then return;end if;
  insert into public.dirt_piles(latitude,longitude,pile_type,cost,active,placement_source,updated_at)
  select q.latitude,q.longitude,q.t,(array[10,25,50,100,250])[q.t+1],true,'system',now() from (
    select c.latitude,c.longitude,floor(random()*5)::smallint t,row_number() over(partition by floor(c.latitude*506.0),floor(c.longitude*506.0*greatest(.15,cos(radians(player_lat)))) order by random()) grid_pick
    from private.walkable_spawn_candidates c
    where c.latitude between player_lat-.0185 and player_lat+.0185
      and c.longitude between player_lon-(.0185/greatest(.15,cos(radians(player_lat)))) and player_lon+(.0185/greatest(.15,cos(radians(player_lat))))
      and private.distance_meters(player_lat,player_lon,c.latitude,c.longitude)<=2000
      and not exists(select 1 from public.dirt_piles d where d.active and d.latitude between c.latitude-.0021 and c.latitude+.0021 and d.longitude between c.longitude-.004 and c.longitude+.004 and private.distance_meters(c.latitude,c.longitude,d.latitude,d.longitude)<220)
      and not exists(select 1 from public.world_bones b where b.active and b.latitude between c.latitude-.0002 and c.latitude+.0002 and b.longitude between c.longitude-.0003 and c.longitude+.0003 and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<10)
  ) q where q.grid_pick=1 order by random() limit needed;
end $$;
revoke all on function private.maintain_dirt_piles(double precision,double precision) from public,anon,authenticated;

create or replace function public.refresh_world_nearby(p_latitude double precision,p_longitude double precision)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();begin
  if uid is null then raise exception 'AUTH_REQUIRED';end if;
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then raise exception 'GPS_REQUIRED';end if;
  perform set_config('statement_timeout','12s',true);perform private.maintain_world_bones(p_latitude,p_longitude);
  perform private.maintain_dirt_piles(p_latitude,p_longitude);perform private.ensure_close_dirt_pile(p_latitude,p_longitude);
  return jsonb_build_object('ok',true,'radius_m',2000,'bone_target',170,'pile_target',30,'bone_spacing_m',100,'pile_spacing_m',220,'close_pile_m',350);
end $$;
revoke execute on function public.refresh_world_nearby(double precision,double precision) from public,anon;
grant execute on function public.refresh_world_nearby(double precision,double precision) to authenticated;
notify pgrst,'reload schema';
