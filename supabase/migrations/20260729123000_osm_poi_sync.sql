create or replace function public.sync_discovered_pois(p_pois jsonb)
returns integer language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid();me public.player_presence%rowtype;x jsonb;n integer:=0;lat double precision;lon double precision;kind text;
begin
 if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
 select * into me from public.player_presence where player_id=uid and updated_at>now()-interval '2 minutes';
 if not found then raise exception 'FRESH_LOCATION_REQUIRED';end if;
 if jsonb_typeof(p_pois)<>'array' or jsonb_array_length(p_pois)>500 then raise exception 'INVALID_POI_BATCH';end if;
 for x in select value from jsonb_array_elements(p_pois) loop
  lat:=(x->>'latitude')::double precision;lon:=(x->>'longitude')::double precision;kind:=x->>'poi_type';
  if kind not in ('dog_park','pet_shop','veterinary','grooming','dog_wash') or private.distance_meters(me.latitude,me.longitude,lat,lon)>20000 then continue;end if;
  insert into public.game_pois(osm_type,osm_id,poi_type,name,latitude,longitude,address,opening_hours,phone,website,has_game_shop,source,active,updated_at)
  values(x->>'osm_type',(x->>'osm_id')::bigint,kind,x->>'name',lat,lon,x->>'address',x->>'opening_hours',x->>'phone',x->>'website',kind in ('dog_park','pet_shop'),'osm',true,now())
  on conflict(osm_type,osm_id) do update set poi_type=excluded.poi_type,name=excluded.name,latitude=excluded.latitude,longitude=excluded.longitude,address=excluded.address,opening_hours=excluded.opening_hours,phone=excluded.phone,website=excluded.website,has_game_shop=excluded.has_game_shop,active=true,updated_at=now();n:=n+1;
 end loop;return n;
end $$;
revoke execute on function public.sync_discovered_pois(jsonb) from public,anon;
grant execute on function public.sync_discovered_pois(jsonb) to authenticated;
