-- Density test for Bro: keep the balanced 36 and add enough organically
-- distributed system bones to reach 100 within five kilometres.
do $expand_bro_bones$
declare
  center record;
  current_count integer;
  added_index integer := 0;
  sector integer;
  band integer;
  sector_width double precision := 2.0*pi()/20.0;
  min_radius double precision;
  max_radius double precision;
  candidate record;
  attempt integer;
begin
  select latitude,longitude into center
  from public.player_presence order by updated_at desc limit 1;
  if not found then raise exception 'PLAYER_POSITION_REQUIRED'; end if;

  select count(*) into current_count
  from public.world_bones
  where active and placement_source='system'
    and private.distance_meters(
      center.latitude,center.longitude,latitude,longitude
    ) <= 5000.0;

  while current_count < 100 loop
    sector:=added_index % 20;
    band:=(added_index / 20) % 5;

    if band=0 then min_radius:=200.0; max_radius:=1200.0;
    elsif band=1 then min_radius:=1200.0; max_radius:=2200.0;
    elsif band=2 then min_radius:=2200.0; max_radius:=3200.0;
    elsif band=3 then min_radius:=3200.0; max_radius:=4100.0;
    else min_radius:=4100.0; max_radius:=4900.0;
    end if;

    candidate:=null;
    for attempt in 1..30 loop
      select * into candidate from private.random_point_in_sector(
        center.latitude,center.longitude,min_radius,max_radius,
        sector*sector_width,(sector+1)*sector_width
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

    if candidate is not null then
      insert into public.world_bones(
        latitude,longitude,bone_type,active,placement_source,updated_at
      ) values (
        candidate.latitude,candidate.longitude,private.random_bone_type(),
        true,'system',now()
      );
      current_count:=current_count+1;
    end if;

    added_index:=added_index+1;
    if added_index>500 then
      raise exception 'COULD_NOT_REACH_TARGET_DENSITY';
    end if;
  end loop;
end
$expand_bro_bones$;
