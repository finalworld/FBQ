-- Slightly denser dirt-pile coverage: 16 active system piles within 3 km
-- instead of 12. Existing spacing and bone-separation rules remain intact.
create or replace function private.maintain_dirt_piles(
  player_lat double precision,
  player_lon double precision
) returns void
language plpgsql volatile security definer set search_path=''
as $$
declare p record;c record;n integer;i integer;t smallint;
begin
  for p in
    select id from public.dirt_piles d
    where d.active and d.placement_source='system'
      and exists(
        select 1 from public.world_bones b
        where b.active and private.distance_meters(d.latitude,d.longitude,b.latitude,b.longitude)<100
      )
    for update skip locked
  loop
    select w.latitude,w.longitude into c
    from private.walkable_spawn_candidates w
    where private.distance_meters(player_lat,player_lon,w.latitude,w.longitude)<=2800
      and not exists(select 1 from public.dirt_piles d where d.active and d.id<>p.id and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<350)
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(w.latitude,w.longitude,b.latitude,b.longitude)<100)
    order by random() limit 1;
    if found then
      update public.dirt_piles set latitude=c.latitude,longitude=c.longitude,updated_at=now() where id=p.id;
    end if;
  end loop;

  for p in
    select id,latitude,longitude from public.dirt_piles
    where not active and respawn_at<=now()
    for update skip locked
  loop
    select w.latitude,w.longitude into c
    from private.walkable_spawn_candidates w
    where private.distance_meters(p.latitude,p.longitude,w.latitude,w.longitude) between 500 and 1000
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<350)
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(w.latitude,w.longitude,b.latitude,b.longitude)<100)
    order by random() limit 1;
    if found then
      t:=floor(random()*5)::smallint;
      update public.dirt_piles
      set latitude=c.latitude,longitude=c.longitude,pile_type=t,
          cost=(array[10,25,50,100,250])[t+1],active=true,
          respawn_at=null,claimed_at=null,generation=generation+1,updated_at=now()
      where id=p.id;
    end if;
  end loop;

  select count(*) into n
  from public.dirt_piles d
  where d.active and private.distance_meters(player_lat,player_lon,d.latitude,d.longitude)<=3000;

  if n<16 then
    for i in n+1..16 loop
      select w.latitude,w.longitude into c
      from private.walkable_spawn_candidates w
      where private.distance_meters(player_lat,player_lon,w.latitude,w.longitude)<=2800
        and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<350)
        and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(w.latitude,w.longitude,b.latitude,b.longitude)<100)
      order by random() limit 1;
      exit when not found;
      t:=floor(random()*5)::smallint;
      insert into public.dirt_piles(latitude,longitude,pile_type,cost,active,placement_source,updated_at)
      values(c.latitude,c.longitude,t,(array[10,25,50,100,250])[t+1],true,'system',now());
    end loop;
  end if;
end $$;

revoke all on function private.maintain_dirt_piles(double precision,double precision)
  from public,anon,authenticated;

-- Fill the new target immediately around recently active accurate players.
do $$
declare v_player record;
begin
  for v_player in
    select pp.latitude,pp.longitude
    from public.player_presence pp
    where pp.updated_at>=now()-interval '24 hours'
      and coalesce(pp.accuracy_m,9999)<=30
  loop
    perform private.maintain_dirt_piles(v_player.latitude,v_player.longitude);
  end loop;
end $$;
