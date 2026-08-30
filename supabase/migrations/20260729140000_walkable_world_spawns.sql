-- Cache OSM-derived walkable points and use them for the global world.
create table if not exists private.walkable_spawn_candidates (
  source_key text primary key,
  latitude double precision not null check(latitude between -90 and 90),
  longitude double precision not null check(longitude between -180 and 180),
  last_seen_at timestamptz not null default now()
);
create index if not exists walkable_spawn_candidates_location_idx
  on private.walkable_spawn_candidates(latitude,longitude);
revoke all on table private.walkable_spawn_candidates from public,anon,authenticated;

create or replace function public.sync_walkable_spawn_candidates(p_points jsonb)
returns integer language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); me record; item jsonb; lat double precision; lon double precision;
  source text; accepted integer:=0; existing_bone record; candidate record;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  select * into me from public.player_presence where player_id=uid;
  if not found or me.updated_at<now()-interval '30 seconds' or me.accuracy_m>30 then
    raise exception 'FRESH_LOCATION_REQUIRED' using errcode='P0001';
  end if;
  if jsonb_typeof(p_points)<>'array' or jsonb_array_length(p_points)>1000 then
    raise exception 'INVALID_WALKABLE_POINTS' using errcode='22023';
  end if;
  for item in select value from jsonb_array_elements(p_points) loop
    begin
      lat:=(item->>'latitude')::double precision;
      lon:=(item->>'longitude')::double precision;
      source:=left(coalesce(nullif(item->>'source_key',''),md5(lat::text||':'||lon::text)),160);
    exception when others then continue;
    end;
    if lat not between -90 and 90 or lon not between -180 and 180
       or private.distance_meters(me.latitude,me.longitude,lat,lon)>5000 then continue; end if;
    insert into private.walkable_spawn_candidates(source_key,latitude,longitude,last_seen_at)
    values(source,lat,lon,now())
    on conflict(source_key) do update set latitude=excluded.latitude,longitude=excluded.longitude,last_seen_at=now();
    accepted:=accepted+1;
  end loop;
  delete from private.walkable_spawn_candidates where last_seen_at<now()-interval '90 days';
  -- Repair earlier radial test placements once trusted walkable points arrive.
  for existing_bone in select id,latitude,longitude from public.world_bones b
    where b.active and b.placement_source='system'
      and private.distance_meters(me.latitude,me.longitude,b.latitude,b.longitude)<=3000
      and not exists(select 1 from private.walkable_spawn_candidates w
        where private.distance_meters(b.latitude,b.longitude,w.latitude,w.longitude)<=35)
    for update skip locked
  loop
    select w.latitude,w.longitude into candidate from private.walkable_spawn_candidates w
    where private.distance_meters(me.latitude,me.longitude,w.latitude,w.longitude) between 100 and 3000
      and not exists(select 1 from public.world_bones other where other.active and other.id<>existing_bone.id
        and private.distance_meters(w.latitude,w.longitude,other.latitude,other.longitude)<100)
    order by random() limit 1;
    if found then update public.world_bones set latitude=candidate.latitude,longitude=candidate.longitude,
      updated_at=now() where id=existing_bone.id; end if;
  end loop;
  perform private.maintain_world_bones(me.latitude,me.longitude);
  perform private.maintain_dirt_piles(me.latitude,me.longitude);
  return accepted;
end $$;

create or replace function private.maintain_world_bones(player_lat double precision,player_lon double precision)
returns void language plpgsql volatile security definer set search_path=''
as $$
declare due_bone record; candidate record; nearby_count integer; created integer:=0;
begin
  if not pg_try_advisory_xact_lock(1179666257) then return; end if;
  for due_bone in select id,latitude,longitude from public.world_bones
    where not active and placement_source='system' and respawn_at<=now()
    order by respawn_at for update skip locked
  loop
    select c.latitude,c.longitude into candidate from private.walkable_spawn_candidates c
    where private.distance_meters(due_bone.latitude,due_bone.longitude,c.latitude,c.longitude) between 250 and 1200
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<100)
    order by random() limit 1;
    if found then update public.world_bones set latitude=candidate.latitude,longitude=candidate.longitude,
      bone_type=private.random_bone_type(),active=true,respawn_at=null,collected_at=null,
      generation=generation+1,updated_at=now() where id=due_bone.id; end if;
  end loop;
  select count(*) into nearby_count from public.world_bones b where b.active and b.placement_source='system'
    and private.distance_meters(player_lat,player_lon,b.latitude,b.longitude)<=3000;
  while nearby_count+created<100 and created<100 loop
    select c.latitude,c.longitude into candidate from private.walkable_spawn_candidates c
    where private.distance_meters(player_lat,player_lon,c.latitude,c.longitude) between 100 and 3000
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<100)
    order by random() limit 1;
    exit when not found;
    insert into public.world_bones(latitude,longitude,bone_type,active,placement_source,updated_at)
    values(candidate.latitude,candidate.longitude,private.random_bone_type(),true,'system',now());
    created:=created+1;
  end loop;
end $$;

create or replace function private.maintain_dirt_piles(player_lat double precision,player_lon double precision)
returns void language plpgsql volatile security definer set search_path=''
as $$
declare p record;c record;n integer;i integer;t smallint;
begin
  for p in select id,latitude,longitude from public.dirt_piles where not active and respawn_at<=now() for update skip locked loop
    select w.latitude,w.longitude into c from private.walkable_spawn_candidates w
    where private.distance_meters(p.latitude,p.longitude,w.latitude,w.longitude) between 500 and 1000
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<750)
    order by random() limit 1;
    if found then t:=floor(random()*5)::smallint;update public.dirt_piles set latitude=c.latitude,longitude=c.longitude,pile_type=t,
      cost=(array[10,25,50,100,250])[t+1],active=true,respawn_at=null,claimed_at=null,generation=generation+1,updated_at=now() where id=p.id;end if;
  end loop;
  select count(*) into n from public.dirt_piles d where d.active and private.distance_meters(player_lat,player_lon,d.latitude,d.longitude)<=3000;
  if n<4 then for i in n+1..4 loop
    select w.latitude,w.longitude into c from private.walkable_spawn_candidates w
    where private.distance_meters(player_lat,player_lon,w.latitude,w.longitude) between 600 and 2800
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<750)
    order by random() limit 1;
    exit when not found;t:=floor(random()*5)::smallint;
    insert into public.dirt_piles(latitude,longitude,pile_type,cost,active,placement_source,updated_at)
    values(c.latitude,c.longitude,t,(array[10,25,50,100,250])[t+1],true,'system',now());
  end loop;end if;
end $$;

revoke all on function private.maintain_world_bones(double precision,double precision) from public,anon,authenticated;
revoke all on function private.maintain_dirt_piles(double precision,double precision) from public,anon,authenticated;
revoke execute on function public.sync_walkable_spawn_candidates(jsonb) from public,anon;
grant execute on function public.sync_walkable_spawn_candidates(jsonb) to authenticated;
