-- Give the map one stable, narrow contract for visible dog poops. Direct table
-- decoding made any policy/schema mismatch look exactly like an empty map.
create or replace function public.list_visible_dog_poops(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_m double precision default 2000
) returns table(
  id uuid,
  owner_player_id uuid,
  dog_id uuid,
  latitude double precision,
  longitude double precision,
  created_at timestamptz,
  expires_at timestamptz
) language sql stable security definer set search_path='' as $$
  select w.id,w.owner_player_id,w.dog_id,w.latitude,w.longitude,w.created_at,w.expires_at
  from public.world_dog_poops w
  where auth.uid() is not null
    and p_latitude between -90 and 90
    and p_longitude between -180 and 180
    and p_radius_m between 1 and 5000
    and w.active
    and w.visible_at<=now()
    and w.expires_at>now()
    and private.distance_meters(p_latitude,p_longitude,w.latitude,w.longitude)<=p_radius_m
  order by w.created_at,w.id;
$$;

revoke execute on function public.list_visible_dog_poops(double precision,double precision,double precision)
  from public,anon;
grant execute on function public.list_visible_dog_poops(double precision,double precision,double precision)
  to authenticated;

notify pgrst,'reload schema';
