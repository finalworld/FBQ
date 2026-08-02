-- Concentrate the live test world around the latest player: exactly 100
-- system bones within 3 km, spread across 20 sectors and five distance bands.

create or replace function private.maintain_world_bones(
  player_lat double precision,
  player_lon double precision
) returns void
language plpgsql volatile security definer set search_path=''
as $$
declare
  due_bone record;
  anchor_bone record;
  candidate record;
  nearby_count integer;
  attempt integer;
  created_count integer := 0;
begin
  if not pg_try_advisory_xact_lock(1179666257) then return; end if;

  for due_bone in
    select id,latitude,longitude from public.world_bones
    where not active and placement_source='system'
      and respawn_at is not null and respawn_at<=now()
    order by respawn_at for update skip locked
  loop
    select * into candidate from private.random_point_from(
      due_bone.latitude,due_bone.longitude,100.0,350.0
    );
    update public.world_bones
    set latitude=candidate.latitude,longitude=candidate.longitude,
        bone_type=private.random_bone_type(),active=true,respawn_at=null,
        collected_at=null,generation=generation+1,updated_at=now()
    where id=due_bone.id;
  end loop;

  select count(*) into nearby_count from public.world_bones b
  where b.active and b.placement_source='system'
    and private.distance_meters(player_lat,player_lon,b.latitude,b.longitude)<=3000.0;

  while nearby_count+created_count<100 and created_count<100 loop
    select b.latitude,b.longitude into anchor_bone from public.world_bones b
    where b.active and b.placement_source='system'
      and private.distance_meters(player_lat,player_lon,b.latitude,b.longitude)<=3000.0
    order by random() limit 1;
    if not found then
      anchor_bone.latitude:=player_lat; anchor_bone.longitude:=player_lon;
    end if;

    candidate:=null;
    for attempt in 1..20 loop
      select * into candidate from private.random_point_from(
        anchor_bone.latitude,anchor_bone.longitude,100.0,350.0
      );
      exit when private.distance_meters(
        player_lat,player_lon,candidate.latitude,candidate.longitude
      )<=3000.0 and not exists (
        select 1 from public.world_bones existing
        where existing.active and private.distance_meters(
          candidate.latitude,candidate.longitude,
          existing.latitude,existing.longitude
        )<100.0
      );
      candidate:=null;
    end loop;
    exit when candidate is null;

    insert into public.world_bones(
      latitude,longitude,bone_type,active,placement_source,updated_at
    ) values (
      candidate.latitude,candidate.longitude,private.random_bone_type(),
      true,'system',now()
    );
    created_count:=created_count+1;
  end loop;
end
$$;

revoke all on function private.maintain_world_bones(
  double precision,double precision
) from public,anon,authenticated;

do $concentrate_bro_bones$
declare
  center record;
  bone_ids uuid[];
  new_id uuid;
  slot integer;
  sector integer;
  band integer;
  sector_width double precision := 2.0*pi()/20.0;
  min_radius double precision;
  max_radius double precision;
  candidate record;
begin
  select latitude,longitude into center
  from public.player_presence order by updated_at desc limit 1;
  if not found then raise exception 'PLAYER_POSITION_REQUIRED'; end if;

  select coalesce(array_agg(id order by created_at,id),'{}'::uuid[])
  into bone_ids from public.world_bones
  where active and placement_source='system';

  while coalesce(array_length(bone_ids,1),0)<100 loop
    insert into public.world_bones(
      latitude,longitude,bone_type,active,placement_source,updated_at
    ) values (
      center.latitude,center.longitude,private.random_bone_type(),
      true,'system',now()
    ) returning id into new_id;
    bone_ids:=array_append(bone_ids,new_id);
  end loop;

  for slot in 0..99 loop
    sector:=slot%20;
    band:=slot/20;
    if band=0 then min_radius:=150.0; max_radius:=700.0;
    elsif band=1 then min_radius:=700.0; max_radius:=1250.0;
    elsif band=2 then min_radius:=1250.0; max_radius:=1800.0;
    elsif band=3 then min_radius:=1800.0; max_radius:=2350.0;
    else min_radius:=2350.0; max_radius:=2950.0;
    end if;

    select * into candidate from private.random_point_in_sector(
      center.latitude,center.longitude,min_radius,max_radius,
      sector*sector_width,(sector+1)*sector_width
    );
    update public.world_bones
    set latitude=candidate.latitude,longitude=candidate.longitude,
        bone_type=private.random_bone_type(),updated_at=now()
    where id=bone_ids[slot+1];
  end loop;

  update public.world_bones set active=false,updated_at=now()
  where placement_source='system' and active and not (id=any(bone_ids[1:100]));
end
$concentrate_bro_bones$;
