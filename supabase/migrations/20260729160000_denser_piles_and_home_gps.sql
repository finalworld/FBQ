-- Physical test tuning: twelve dirt piles within 3 km, and a less brittle
-- home-placement freshness window while retaining the <=30 m GPS gate.
create or replace function private.maintain_dirt_piles(player_lat double precision,player_lon double precision)
returns void language plpgsql volatile security definer set search_path=''
as $$
declare p record;c record;n integer;i integer;t smallint;
begin
  for p in select id,latitude,longitude from public.dirt_piles where not active and respawn_at<=now() for update skip locked loop
    select w.latitude,w.longitude into c from private.walkable_spawn_candidates w
    where private.distance_meters(p.latitude,p.longitude,w.latitude,w.longitude) between 500 and 1000
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<350)
    order by random() limit 1;
    if found then
      t:=floor(random()*5)::smallint;
      update public.dirt_piles set latitude=c.latitude,longitude=c.longitude,pile_type=t,
        cost=(array[10,25,50,100,250])[t+1],active=true,respawn_at=null,claimed_at=null,
        generation=generation+1,updated_at=now() where id=p.id;
    end if;
  end loop;

  select count(*) into n from public.dirt_piles d where d.active
    and private.distance_meters(player_lat,player_lon,d.latitude,d.longitude)<=3000;
  if n<12 then
    for i in n+1..12 loop
      select w.latitude,w.longitude into c from private.walkable_spawn_candidates w
      where private.distance_meters(player_lat,player_lon,w.latitude,w.longitude) between 350 and 2800
        and not exists(select 1 from public.dirt_piles d where d.active
          and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<350)
      order by random() limit 1;
      exit when not found;
      t:=floor(random()*5)::smallint;
      insert into public.dirt_piles(latitude,longitude,pile_type,cost,active,placement_source,updated_at)
      values(c.latitude,c.longitude,t,(array[10,25,50,100,250])[t+1],true,'system',now());
    end loop;
  end if;
end $$;

create or replace function public.set_home_here()
returns table(latitude double precision,longitude double precision,next_move_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); me public.player_presence%rowtype; last_change timestamptz;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  select * into me from public.player_presence where player_id=uid;
  if not found or me.updated_at<now()-interval '60 seconds' or me.accuracy_m>30 then
    raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';
  end if;
  select home_changed_at into last_change from public.profiles where id=uid for update;
  if last_change is not null and last_change+interval '24 hours'>now() then
    raise exception 'HOME_COOLDOWN' using errcode='P0001',detail=(last_change+interval '24 hours')::text;
  end if;
  update public.profiles set home_lat=me.latitude,home_lon=me.longitude,
    home_changed_at=now(),updated_at=now() where id=uid;
  latitude:=me.latitude; longitude:=me.longitude;
  next_move_at:=now()+interval '24 hours'; return next;
end $$;

revoke all on function private.maintain_dirt_piles(double precision,double precision) from public,anon,authenticated;
revoke execute on function public.set_home_here() from public,anon;
grant execute on function public.set_home_here() to authenticated;

do $refresh_piles$
declare c record;
begin
  select latitude,longitude into c from public.player_presence
  where updated_at>now()-interval '1 day' order by updated_at desc limit 1;
  if found then perform private.maintain_dirt_piles(c.latitude,c.longitude); end if;
end $refresh_piles$;
