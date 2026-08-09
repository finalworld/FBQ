-- Guarantee that an active area has useful bones close enough to begin a walk.
-- The previous world maintainer only targeted 100 bones inside 3 km; all 100
-- could therefore land far from the player. There is deliberately no empty
-- radius around the player/home.
create or replace function private.ensure_close_bones(
  player_lat double precision,
  player_lon double precision
) returns void
language plpgsql volatile security definer set search_path=''
as $$
declare
  close_count integer;
  candidate record;
  created integer := 0;
begin
  select count(*) into close_count
  from public.world_bones b
  where b.active and b.placement_source='system'
    and private.distance_meters(player_lat,player_lon,b.latitude,b.longitude)<=350;

  while close_count + created < 5 and created < 5 loop
    select c.latitude,c.longitude into candidate
    from private.walkable_spawn_candidates c
    where private.distance_meters(player_lat,player_lon,c.latitude,c.longitude)<=350
      and not exists (
        select 1 from public.world_bones b
        where b.active
          and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<55
      )
      and not exists (
        select 1 from public.dirt_piles d
        where d.active
          and private.distance_meters(c.latitude,c.longitude,d.latitude,d.longitude)<75
      )
    order by random() limit 1;
    exit when not found;
    insert into public.world_bones(latitude,longitude,bone_type,active,placement_source,updated_at)
    values(candidate.latitude,candidate.longitude,private.random_bone_type(),true,'system',now());
    created := created + 1;
  end loop;
end $$;

revoke all on function private.ensure_close_bones(double precision,double precision)
  from public,anon,authenticated;

-- Presence updates already invoke maintain_world_bones. Wrap the current
-- function so every accurate update also enforces the close-area minimum.
create or replace function private.maintain_world_bones(
  player_lat double precision,
  player_lon double precision
) returns void
language plpgsql volatile security definer set search_path=''
as $$
declare
  due_bone record; stale_bone record; candidate record; nearby_count integer;
  created integer:=0; replacement smallint; attempts integer;
begin
  if not pg_try_advisory_xact_lock(1179666257) then return; end if;
  for stale_bone in select id,bone_type from public.world_bones where active and placement_source='system' and updated_at<=now()-interval '10 hours' order by updated_at for update skip locked loop
    attempts:=0; loop replacement:=private.random_bone_type(); attempts:=attempts+1; exit when replacement<>stale_bone.bone_type or attempts>=20; end loop;
    if replacement=stale_bone.bone_type then replacement:=case when stale_bone.bone_type=0 then 1 else 0 end; end if;
    update public.world_bones set bone_type=replacement,generation=generation+1,updated_at=now() where id=stale_bone.id;
  end loop;
  for due_bone in select id,latitude,longitude from public.world_bones where not active and placement_source='system' and respawn_at<=now() order by respawn_at for update skip locked loop
    select c.latitude,c.longitude into candidate from private.walkable_spawn_candidates c
    where private.distance_meters(due_bone.latitude,due_bone.longitude,c.latitude,c.longitude) between 250 and 1200
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<100)
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(c.latitude,c.longitude,d.latitude,d.longitude)<100)
    order by random() limit 1;
    if found then update public.world_bones set latitude=candidate.latitude,longitude=candidate.longitude,bone_type=private.random_bone_type(),active=true,respawn_at=null,collected_at=null,generation=generation+1,updated_at=now() where id=due_bone.id; end if;
  end loop;
  perform private.ensure_close_bones(player_lat,player_lon);
  select count(*) into nearby_count from public.world_bones b where b.active and b.placement_source='system' and private.distance_meters(player_lat,player_lon,b.latitude,b.longitude)<=3000;
  while nearby_count+created<100 and created<100 loop
    select c.latitude,c.longitude into candidate from private.walkable_spawn_candidates c
    where private.distance_meters(player_lat,player_lon,c.latitude,c.longitude)<=3000
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<100)
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(c.latitude,c.longitude,d.latitude,d.longitude)<100)
    order by random() limit 1;
    exit when not found;
    insert into public.world_bones(latitude,longitude,bone_type,active,placement_source,updated_at)
    values(candidate.latitude,candidate.longitude,private.random_bone_type(),true,'system',now());
    created:=created+1;
  end loop;
end $$;

revoke all on function private.maintain_world_bones(double precision,double precision)
  from public,anon,authenticated;

-- Seed the guarantee immediately around recently active, accurate players.
-- Normal gameplay keeps invoking the same maintenance through presence updates.
do $$
declare
  v_player record;
begin
  for v_player in
    select pp.latitude, pp.longitude
    from public.player_presence pp
    where pp.updated_at >= now() - interval '24 hours'
      and coalesce(pp.accuracy_m, 9999) <= 30
  loop
    perform private.maintain_world_bones(v_player.latitude, v_player.longitude);
  end loop;
end;
$$;
