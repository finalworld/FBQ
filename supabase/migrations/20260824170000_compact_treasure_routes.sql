-- Compact treasure routes around the actual start point.
-- Straight-line checkpoint distance is deliberately ~82% of the selected
-- length to leave room for real streets, corners and path detours.
create or replace function private.fill_treasure_checkpoints(
  p_hunt uuid,p_lat float8,p_lon float8,p_km integer,p_needed integer
) returns void language plpgsql security definer set search_path='' as $$
declare
  target_m float8:=p_km*1000.0;
  route_target float8:=p_km*820.0;
  ring_radius float8;
  phase float8;
  angle float8;
  ideal_lat float8;
  ideal_lon float8;
  tolerance float8;
  attempt integer;
  seq integer;
  i integer;
  r record;
  chosen_lat float8[];
  chosen_lon float8[];
  route_m float8;
  previous_lat float8;
  previous_lon float8;
  complete boolean;
begin
  if p_needed<2 then raise exception 'INVALID_CHECKPOINT_COUNT';end if;
  -- Distance from centre to first point plus the chords between the rest.
  ring_radius:=route_target/(1.0+(p_needed-1)*2.0*sin(pi()/p_needed));

  for attempt in 1..12 loop
    phase:=random()*2*pi();
    tolerance:=least(210.0,90.0+attempt*10.0);
    chosen_lat:='{}';chosen_lon:='{}';route_m:=0;
    previous_lat:=p_lat;previous_lon:=p_lon;complete:=true;

    for seq in 1..p_needed loop
      angle:=phase+2*pi()*(seq-1)/p_needed;
      ideal_lat:=p_lat+(ring_radius*cos(angle))/111320.0;
      ideal_lon:=p_lon+(ring_radius*sin(angle))/(111320.0*greatest(.15,cos(radians(p_lat))));

      select c.latitude,c.longitude into r
      from private.walkable_spawn_candidates c
      where c.last_seen_at>now()-interval '45 days'
        and c.latitude between ideal_lat-(tolerance/111320.0) and ideal_lat+(tolerance/111320.0)
        and c.longitude between ideal_lon-(tolerance/(111320.0*greatest(.15,cos(radians(p_lat)))))
                            and ideal_lon+(tolerance/(111320.0*greatest(.15,cos(radians(p_lat)))))
        and private.distance_meters(ideal_lat,ideal_lon,c.latitude,c.longitude)<=tolerance
        and private.distance_meters(p_lat,p_lon,c.latitude,c.longitude)<=ring_radius+tolerance
        and not exists(
          select 1 from generate_subscripts(chosen_lat,1) s
          where private.distance_meters(chosen_lat[s],chosen_lon[s],c.latitude,c.longitude)<70
        )
      order by private.distance_meters(ideal_lat,ideal_lon,c.latitude,c.longitude),random()
      limit 1;

      if not found then complete:=false;exit;end if;
      route_m:=route_m+private.distance_meters(previous_lat,previous_lon,r.latitude,r.longitude);
      chosen_lat:=array_append(chosen_lat,r.latitude);chosen_lon:=array_append(chosen_lon,r.longitude);
      previous_lat:=r.latitude;previous_lon:=r.longitude;
    end loop;

    if complete and route_m between target_m*.68 and target_m*1.02 then
      for i in 1..p_needed loop
        insert into public.treasure_checkpoints(hunt_id,sequence,latitude,longitude)
        values(p_hunt,i,chosen_lat[i],chosen_lon[i]);
      end loop;
      return;
    end if;
  end loop;
  raise exception 'NOT_ENOUGH_WALKABLE_POINTS';
end $$;

revoke all on function private.fill_treasure_checkpoints(uuid,double precision,double precision,integer,integer)
  from public,anon,authenticated;
notify pgrst,'reload schema';
