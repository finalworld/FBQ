-- Bones and dirt piles must remain visually and physically distinct.
-- Enforce a 100 m cross-type clearance for creation, respawn and repair.
create or replace function private.maintain_world_bones(player_lat double precision,player_lon double precision)
returns void language plpgsql volatile security definer set search_path=''
as $$
declare due_bone record; stale_bone record; candidate record; nearby_count integer;
  created integer:=0; replacement smallint; attempts integer;
begin
  if not pg_try_advisory_xact_lock(1179666257) then return; end if;

  for stale_bone in select id,bone_type from public.world_bones
    where active and placement_source='system' and updated_at<=now()-interval '10 hours'
    order by updated_at for update skip locked
  loop
    attempts:=0;
    loop replacement:=private.random_bone_type();attempts:=attempts+1;
      exit when replacement<>stale_bone.bone_type or attempts>=20;end loop;
    if replacement=stale_bone.bone_type then replacement:=case when stale_bone.bone_type=0 then 1 else 0 end;end if;
    update public.world_bones set bone_type=replacement,generation=generation+1,updated_at=now() where id=stale_bone.id;
  end loop;

  for due_bone in select id,latitude,longitude from public.world_bones
    where not active and placement_source='system' and respawn_at<=now()
    order by respawn_at for update skip locked
  loop
    select c.latitude,c.longitude into candidate from private.walkable_spawn_candidates c
    where private.distance_meters(due_bone.latitude,due_bone.longitude,c.latitude,c.longitude) between 250 and 1200
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<100)
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(c.latitude,c.longitude,d.latitude,d.longitude)<100)
    order by random() limit 1;
    if found then update public.world_bones set latitude=candidate.latitude,longitude=candidate.longitude,
      bone_type=private.random_bone_type(),active=true,respawn_at=null,collected_at=null,
      generation=generation+1,updated_at=now() where id=due_bone.id;end if;
  end loop;

  select count(*) into nearby_count from public.world_bones b where b.active and b.placement_source='system'
    and private.distance_meters(player_lat,player_lon,b.latitude,b.longitude)<=3000;
  while nearby_count+created<100 and created<100 loop
    select c.latitude,c.longitude into candidate from private.walkable_spawn_candidates c
    where private.distance_meters(player_lat,player_lon,c.latitude,c.longitude) between 100 and 3000
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<100)
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(c.latitude,c.longitude,d.latitude,d.longitude)<100)
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
  -- Repair any existing system pile that overlaps an active bone.
  for p in select id from public.dirt_piles d where d.active and d.placement_source='system'
    and exists(select 1 from public.world_bones b where b.active
      and private.distance_meters(d.latitude,d.longitude,b.latitude,b.longitude)<100)
    for update skip locked
  loop
    select w.latitude,w.longitude into c from private.walkable_spawn_candidates w
    where private.distance_meters(player_lat,player_lon,w.latitude,w.longitude) between 350 and 2800
      and not exists(select 1 from public.dirt_piles d where d.active and d.id<>p.id
        and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<350)
      and not exists(select 1 from public.world_bones b where b.active
        and private.distance_meters(w.latitude,w.longitude,b.latitude,b.longitude)<100)
    order by random() limit 1;
    if found then update public.dirt_piles set latitude=c.latitude,longitude=c.longitude,updated_at=now() where id=p.id;end if;
  end loop;

  for p in select id,latitude,longitude from public.dirt_piles where not active and respawn_at<=now() for update skip locked loop
    select w.latitude,w.longitude into c from private.walkable_spawn_candidates w
    where private.distance_meters(p.latitude,p.longitude,w.latitude,w.longitude) between 500 and 1000
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<350)
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(w.latitude,w.longitude,b.latitude,b.longitude)<100)
    order by random() limit 1;
    if found then t:=floor(random()*5)::smallint;update public.dirt_piles set latitude=c.latitude,longitude=c.longitude,pile_type=t,
      cost=(array[10,25,50,100,250])[t+1],active=true,respawn_at=null,claimed_at=null,generation=generation+1,updated_at=now() where id=p.id;end if;
  end loop;

  select count(*) into n from public.dirt_piles d where d.active and private.distance_meters(player_lat,player_lon,d.latitude,d.longitude)<=3000;
  if n<12 then for i in n+1..12 loop
    select w.latitude,w.longitude into c from private.walkable_spawn_candidates w
    where private.distance_meters(player_lat,player_lon,w.latitude,w.longitude) between 350 and 2800
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<350)
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(w.latitude,w.longitude,b.latitude,b.longitude)<100)
    order by random() limit 1;
    exit when not found;t:=floor(random()*5)::smallint;
    insert into public.dirt_piles(latitude,longitude,pile_type,cost,active,placement_source,updated_at)
    values(c.latitude,c.longitude,t,(array[10,25,50,100,250])[t+1],true,'system',now());
  end loop;end if;
end $$;

revoke all on function private.maintain_world_bones(double precision,double precision) from public,anon,authenticated;
revoke all on function private.maintain_dirt_piles(double precision,double precision) from public,anon,authenticated;

do $repair_world_overlap$
declare c record;
begin
  select latitude,longitude into c from public.player_presence order by updated_at desc limit 1;
  if found then
    -- Existing dense system bones can leave no valid 350 m pile destination.
    -- Remove only the overlapping generated bones; the maintainer immediately
    -- replaces them at valid random positions while preserving the target count.
    delete from public.world_bones b
    where b.active and b.placement_source='system'
      and exists(select 1 from public.dirt_piles d
        where d.active and d.placement_source='system'
          and private.distance_meters(b.latitude,b.longitude,d.latitude,d.longitude)<100);
    perform private.maintain_dirt_piles(c.latitude,c.longitude);
    perform private.maintain_world_bones(c.latitude,c.longitude);
  end if;
end $repair_world_overlap$;
