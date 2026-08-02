-- Keep four uncommon dirt piles around the latest active area and respawn
-- claimed piles 500-1000 metres away after their 5-10 minute cooldown.
create or replace function private.maintain_dirt_piles(player_lat double precision,player_lon double precision)
returns void language plpgsql volatile security definer set search_path=''
as $$
declare p record;c record;n integer;i integer;t smallint;attempt integer;
begin
  for p in select id,latitude,longitude from public.dirt_piles
    where not active and respawn_at<=now() for update skip locked
  loop
    select * into c from private.random_point_from(p.latitude,p.longitude,500.0,1000.0);
    t:=floor(random()*5)::smallint;
    update public.dirt_piles set latitude=c.latitude,longitude=c.longitude,pile_type=t,
      cost=(array[10,25,50,100,250])[t+1],active=true,respawn_at=null,claimed_at=null,
      generation=generation+1,updated_at=now() where id=p.id;
  end loop;
  select count(*) into n from public.dirt_piles d where d.active and
    private.distance_meters(player_lat,player_lon,d.latitude,d.longitude)<=3000;
  if n < 4 then
  for i in n+1..4 loop
    -- Prefer 750+ metres between piles so each one becomes a deliberate walk.
    -- After twelve attempts we accept the best random point rather than leave
    -- an area without its promised pile count.
    for attempt in 1..12 loop
      select * into c from private.random_point_from(player_lat,player_lon,600.0,2800.0);
      exit when not exists(
        select 1 from public.dirt_piles d where d.active and
          private.distance_meters(c.latitude,c.longitude,d.latitude,d.longitude)<750
      );
    end loop;
    t:=floor(random()*5)::smallint;
    insert into public.dirt_piles(latitude,longitude,pile_type,cost,active,updated_at)
    values(c.latitude,c.longitude,t,(array[10,25,50,100,250])[t+1],true,now());
  end loop;
  end if;
end $$;
revoke all on function private.maintain_dirt_piles(double precision,double precision) from public,anon,authenticated;

create or replace function public.update_presence(
  latitude double precision,longitude double precision,accuracy_m real,
  heading real default 0,speed_mps real default null,is_background boolean default false
) returns timestamptz language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid();stamp timestamptz:=clock_timestamp();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  perform private.assert_active_player(uid);
  if latitude not between -90 and 90 or longitude not between -180 and 180 or accuracy_m<=0 or accuracy_m>10000 then raise exception 'INVALID_LOCATION' using errcode='22023';end if;
  insert into public.player_presence(player_id,latitude,longitude,accuracy_m,heading,speed_mps,is_background,moved_at,updated_at)
  values(uid,latitude,longitude,accuracy_m,coalesce(heading,0),speed_mps,is_background,stamp,stamp)
  on conflict(player_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,
    accuracy_m=excluded.accuracy_m,heading=excluded.heading,speed_mps=excluded.speed_mps,
    is_background=excluded.is_background,moved_at=case when private.distance_meters(
      public.player_presence.latitude,public.player_presence.longitude,excluded.latitude,excluded.longitude)>2 then stamp else public.player_presence.moved_at end,updated_at=stamp;
  if accuracy_m<=30 then perform private.maintain_world_bones(latitude,longitude);perform private.maintain_dirt_piles(latitude,longitude);end if;
  return stamp;
end $$;
revoke execute on function public.update_presence(double precision,double precision,real,real,real,boolean) from public,anon;
grant execute on function public.update_presence(double precision,double precision,real,real,real,boolean) to authenticated;

do $seed_piles$ declare c record;begin
 select latitude,longitude into c from public.player_presence order by updated_at desc limit 1;
 if found then perform private.maintain_dirt_piles(c.latitude,c.longitude);end if;
end $seed_piles$;
