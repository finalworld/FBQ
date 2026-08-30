-- Organic loose-bone spawning. The server owns both rarity and coordinates.

create or replace function private.random_bone_type()
returns smallint
language plpgsql volatile security definer set search_path=''
as $$
declare
  roll integer;
  running_weight integer := 0;
  selected smallint;
  item record;
begin
  select floor(random() * greatest(1, sum(spawn_weight)))::integer
    into roll
  from public.bone_types;

  for item in
    select id, spawn_weight from public.bone_types order by id
  loop
    running_weight := running_weight + item.spawn_weight;
    if roll < running_weight then
      selected := item.id;
      exit;
    end if;
  end loop;

  return coalesce(selected, 0);
end
$$;

create or replace function private.random_point_from(
  origin_lat double precision,
  origin_lon double precision,
  minimum_m double precision,
  maximum_m double precision
) returns table(latitude double precision, longitude double precision)
language plpgsql volatile set search_path=''
as $$
declare
  earth_radius constant double precision := 6371000.0;
  bearing double precision := random() * 2.0 * pi();
  -- sqrt gives an even distribution over the annulus instead of bunching
  -- every result close to its anchor.
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
  -- Presence updates can arrive concurrently. Only one request performs
  -- maintenance; the others continue without waiting.
  if not pg_try_advisory_xact_lock(1179666257) then
    return;
  end if;

  -- A collected system bone returns somewhere else after its timer expires.
  -- Its rarity is rolled again so fixed farming routes cannot target one type.
  for due_bone in
    select id, latitude, longitude
    from public.world_bones
    where not active
      and placement_source = 'system'
      and respawn_at is not null
      and respawn_at <= now()
    order by respawn_at
    for update skip locked
  loop
    select * into candidate
    from private.random_point_from(
      due_bone.latitude, due_bone.longitude, 100.0, 350.0
    );

    update public.world_bones
    set latitude = candidate.latitude,
        longitude = candidate.longitude,
        bone_type = private.random_bone_type(),
        active = true,
        respawn_at = null,
        collected_at = null,
        generation = generation + 1,
        updated_at = now()
    where id = due_bone.id;
  end loop;

  select count(*) into nearby_count
  from public.world_bones b
  where b.active
    and private.distance_meters(
      player_lat, player_lon, b.latitude, b.longitude
    ) <= 2500.0;

  -- Keep a modest local population. New candidates grow from random existing
  -- anchors, producing irregular walking routes instead of a grid or ring.
  while nearby_count + created_count < 24 and created_count < 24 loop
    select b.latitude, b.longitude into anchor_bone
    from public.world_bones b
    where b.active
      and private.distance_meters(
        player_lat, player_lon, b.latitude, b.longitude
      ) <= 2500.0
    order by random()
    limit 1;

    if not found then
      anchor_bone.latitude := player_lat;
      anchor_bone.longitude := player_lon;
    end if;

    candidate := null;
    for attempt in 1..12 loop
      select * into candidate
      from private.random_point_from(
        anchor_bone.latitude, anchor_bone.longitude, 100.0, 350.0
      );

      exit when not exists (
        select 1 from public.world_bones existing
        where existing.active
          and private.distance_meters(
            candidate.latitude, candidate.longitude,
            existing.latitude, existing.longitude
          ) < 100.0
      );
      candidate := null;
    end loop;

    -- A crowded area may fail all attempts. Stop cleanly instead of forcing
    -- two bones on top of each other.
    exit when candidate is null;

    insert into public.world_bones(
      latitude, longitude, bone_type, active, placement_source, updated_at
    ) values (
      candidate.latitude, candidate.longitude,
      private.random_bone_type(), true, 'system', now()
    );
    created_count := created_count + 1;
  end loop;
end
$$;

revoke all on function private.random_bone_type()
  from public, anon, authenticated;
revoke all on function private.random_point_from(
  double precision, double precision, double precision, double precision
) from public, anon, authenticated;
revoke all on function private.maintain_world_bones(
  double precision, double precision
) from public, anon, authenticated;

-- Presence is already the trusted server entry point for GPS updates. Run
-- light maintenance there only when the submitted fix is accurate enough.
create or replace function public.update_presence(
  latitude double precision, longitude double precision, accuracy_m real,
  heading real default 0, speed_mps real default null,
  is_background boolean default false
) returns timestamptz language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); stamp timestamptz:=clock_timestamp();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  if latitude not between -90 and 90 or longitude not between -180 and 180
     or accuracy_m<=0 or accuracy_m>10000 then
    raise exception 'INVALID_LOCATION' using errcode='22023';
  end if;
  insert into public.player_presence
    (player_id,latitude,longitude,accuracy_m,heading,speed_mps,is_background,moved_at,updated_at)
  values(uid,latitude,longitude,accuracy_m,coalesce(heading,0),speed_mps,is_background,stamp,stamp)
  on conflict(player_id) do update set
    latitude=excluded.latitude,longitude=excluded.longitude,
    accuracy_m=excluded.accuracy_m,heading=excluded.heading,
    speed_mps=excluded.speed_mps,is_background=excluded.is_background,
    moved_at=case when private.distance_meters(
      public.player_presence.latitude,public.player_presence.longitude,
      excluded.latitude,excluded.longitude)>2 then stamp
      else public.player_presence.moved_at end,
    updated_at=stamp;

  if accuracy_m <= 30 then
    perform private.maintain_world_bones(latitude, longitude);
  end if;
  return stamp;
end
$$;

revoke execute on function public.update_presence(
  double precision,double precision,real,real,real,boolean
) from public,anon;
grant execute on function public.update_presence(
  double precision,double precision,real,real,real,boolean
) to authenticated;

-- Shuffle the current test grid once around the latest accurate player.
do $shuffle$
declare
  center record;
  bone record;
  candidate record;
  attempt integer;
begin
  select latitude, longitude into center
  from public.player_presence
  where accuracy_m <= 30
  order by updated_at desc
  limit 1;

  if found then
    for bone in
      select id from public.world_bones
      where active and placement_source = 'system'
      order by created_at, id
    loop
      candidate := null;
      for attempt in 1..20 loop
        select * into candidate
        from private.random_point_from(
          center.latitude, center.longitude, 150.0, 2400.0
        );
        exit when not exists (
          select 1 from public.world_bones existing
          where existing.active and existing.id <> bone.id
            and private.distance_meters(
              candidate.latitude, candidate.longitude,
              existing.latitude, existing.longitude
            ) < 100.0
        );
        candidate := null;
      end loop;

      if candidate is not null then
        update public.world_bones
        set latitude = candidate.latitude,
            longitude = candidate.longitude,
            bone_type = private.random_bone_type(),
            updated_at = now()
        where id = bone.id;
      end if;
    end loop;
  end if;
end
$shuffle$;
