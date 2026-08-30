-- Temporary 0.400 testing helper. The app calls this once after its first
-- accurate GPS fix. Reuse one row per player so test data cannot accumulate.
create or replace function public.place_startup_test_bone(
  latitude double precision,
  longitude double precision
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
  uid uuid := auth.uid();
  source_tag text;
  result uuid;
begin
  if uid is null then
    raise exception 'AUTH_REQUIRED' using errcode='28000';
  end if;
  perform private.assert_active_player(uid);

  if latitude not between -90 and 90 or longitude not between -180 and 180 then
    raise exception 'INVALID_LOCATION' using errcode='22023';
  end if;

  source_tag := 'startup_test:' || uid::text;

  select id into result
  from public.world_bones
  where placement_source = source_tag
  order by created_at
  limit 1
  for update;

  if found then
    update public.world_bones
    set latitude = place_startup_test_bone.latitude,
        longitude = place_startup_test_bone.longitude,
        bone_type = 0,
        active = true,
        respawn_at = null,
        collected_at = null,
        generation = generation + 1,
        updated_at = now()
    where id = result;
  else
    insert into public.world_bones(
      latitude, longitude, bone_type, active, placement_source, updated_at
    ) values (
      place_startup_test_bone.latitude,
      place_startup_test_bone.longitude,
      0, true, source_tag, now()
    ) returning id into result;
  end if;

  return result;
end
$$;

revoke all on function public.place_startup_test_bone(
  double precision, double precision
) from public, anon;
grant execute on function public.place_startup_test_bone(
  double precision, double precision
) to authenticated;
