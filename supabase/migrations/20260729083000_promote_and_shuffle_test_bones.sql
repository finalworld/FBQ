-- Promote the manually seeded 24-bone grid into the organic system pool.
do $shuffle_test_bones$
declare
  center record;
  bone record;
  candidate record;
  attempt integer;
begin
  select latitude, longitude into center
  from public.player_presence
  order by updated_at desc
  limit 1;

  if not found then
    raise exception 'PLAYER_POSITION_REQUIRED';
  end if;

  for bone in
    select id
    from public.world_bones
    where placement_source = 'initial_test_seed'
    order by created_at, id
  loop
    candidate := null;

    for attempt in 1..30 loop
      select * into candidate
      from private.random_point_from(
        center.latitude, center.longitude, 150.0, 2400.0
      );

      exit when not exists (
        select 1
        from public.world_bones existing
        where existing.active
          and existing.id <> bone.id
          and existing.placement_source <> 'initial_test_seed'
          and private.distance_meters(
            candidate.latitude, candidate.longitude,
            existing.latitude, existing.longitude
          ) < 100.0
      );
      candidate := null;
    end loop;

    if candidate is null then
      raise exception 'COULD_NOT_PLACE_TEST_BONE';
    end if;

    update public.world_bones
    set latitude = candidate.latitude,
        longitude = candidate.longitude,
        bone_type = private.random_bone_type(),
        placement_source = 'system',
        updated_at = now()
    where id = bone.id;
  end loop;
end
$shuffle_test_bones$;
