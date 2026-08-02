-- Give a town-sized area organic but balanced coverage. Pure uniform random
-- can leave an entire side of town empty, so the initial distribution uses
-- twelve broad sectors and three independently random distance bands.

create or replace function private.random_point_in_sector(
  origin_lat double precision,
  origin_lon double precision,
  minimum_m double precision,
  maximum_m double precision,
  minimum_bearing double precision,
  maximum_bearing double precision
) returns table(latitude double precision, longitude double precision)
language plpgsql volatile set search_path=''
as $$
declare
  earth_radius constant double precision := 6371000.0;
  bearing double precision := minimum_bearing
    + random() * (maximum_bearing - minimum_bearing);
  distance_m double precision :=
    sqrt(random() * (maximum_m * maximum_m - minimum_m * minimum_m)
      + minimum_m * minimum_m);
  angular_distance double precision := distance_m / earth_radius;
  lat1 double precision := radians(origin_lat);
  lon1 double precision := radians(origin_lon);
  lat2 double precision;
  lon2 double precision;
begin
  lat2 := asin(
    sin(lat1) * cos(angular_distance)
    + cos(lat1) * sin(angular_distance) * cos(bearing)
  );
  lon2 := lon1 + atan2(
    sin(bearing) * sin(angular_distance) * cos(lat1),
    cos(angular_distance) - sin(lat1) * sin(lat2)
  );
  latitude := degrees(lat2);
  longitude := degrees(lon2);
  return next;
end
$$;

revoke all on function private.random_point_in_sector(
  double precision, double precision, double precision,
  double precision, double precision, double precision
) from public, anon, authenticated;

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
    select id, latitude, longitude
    from public.world_bones
    where not active and placement_source = 'system'
      and respawn_at is not null and respawn_at <= now()
    order by respawn_at for update skip locked
  loop
    select * into candidate from private.random_point_from(
      due_bone.latitude, due_bone.longitude, 100.0, 350.0
    );
    update public.world_bones
    set latitude=candidate.latitude, longitude=candidate.longitude,
        bone_type=private.random_bone_type(), active=true,
        respawn_at=null, collected_at=null, generation=generation+1,
        updated_at=now()
    where id=due_bone.id;
  end loop;

  select count(*) into nearby_count
  from public.world_bones b
  where b.active and b.placement_source='system'
    and private.distance_meters(
      player_lat,player_lon,b.latitude,b.longitude
    ) <= 5000.0;

  while nearby_count + created_count < 36 and created_count < 36 loop
    select b.latitude,b.longitude into anchor_bone
    from public.world_bones b
    where b.active and b.placement_source='system'
      and private.distance_meters(
        player_lat,player_lon,b.latitude,b.longitude
      ) <= 5000.0
    order by random() limit 1;
    if not found then
      anchor_bone.latitude:=player_lat; anchor_bone.longitude:=player_lon;
    end if;

    candidate:=null;
    for attempt in 1..12 loop
      select * into candidate from private.random_point_from(
        anchor_bone.latitude,anchor_bone.longitude,100.0,350.0
      );
      exit when not exists (
        select 1 from public.world_bones existing
        where existing.active and private.distance_meters(
          candidate.latitude,candidate.longitude,
          existing.latitude,existing.longitude
        ) < 100.0
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

-- Rebalance the present test area once around the latest player position.
do $balanced_shuffle$
declare
  center record;
  bone_ids uuid[];
  new_id uuid;
  slot integer;
  sector integer;
  band integer;
  min_radius double precision;
  max_radius double precision;
  sector_width double precision := 2.0*pi()/12.0;
  candidate record;
begin
  select latitude,longitude into center
  from public.player_presence order by updated_at desc limit 1;
  if not found then raise exception 'PLAYER_POSITION_REQUIRED'; end if;

  select coalesce(array_agg(id order by created_at,id),'{}'::uuid[])
    into bone_ids
  from public.world_bones
  where active and placement_source='system'
    and private.distance_meters(
      center.latitude,center.longitude,latitude,longitude
    ) <= 10000.0;

  while coalesce(array_length(bone_ids,1),0) < 36 loop
    insert into public.world_bones(
      latitude,longitude,bone_type,active,placement_source,updated_at
    ) values (
      center.latitude,center.longitude,private.random_bone_type(),
      true,'system',now()
    ) returning id into new_id;
    bone_ids:=array_append(bone_ids,new_id);
  end loop;

  for slot in 0..35 loop
    sector:=slot % 12;
    band:=slot / 12;
    if band=0 then min_radius:=250.0; max_radius:=1600.0;
    elsif band=1 then min_radius:=1600.0; max_radius:=3000.0;
    else min_radius:=3000.0; max_radius:=4800.0;
    end if;

    select * into candidate from private.random_point_in_sector(
      center.latitude,center.longitude,min_radius,max_radius,
      sector*sector_width,(sector+1)*sector_width
    );

    update public.world_bones
    set latitude=candidate.latitude, longitude=candidate.longitude,
        bone_type=private.random_bone_type(), updated_at=now()
    where id=bone_ids[slot+1];
  end loop;
end
$balanced_shuffle$;
