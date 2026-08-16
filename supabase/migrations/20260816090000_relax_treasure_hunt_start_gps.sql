-- Starting a hunt only needs a usable starting area. Individual checkpoint
-- claims keep their stricter proximity checks, so accepting a coarse phone
-- fix here does not make checkpoints collectible from farther away.
create or replace function public.start_treasure_hunt(
  p_length_km integer,
  p_points jsonb,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_m double precision
) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  uid uuid:=auth.uid();hid uuid:=gen_random_uuid();team uuid;needed integer;cost integer;
  presence public.player_presence%rowtype;
begin
  if p_length_km not between 1 and 10 then raise exception 'INVALID_LENGTH';end if;
  if exists(select 1 from public.treasure_hunt_participants hp join public.treasure_hunts h on h.id=hp.hunt_id where hp.player_id=uid and h.status='active') then raise exception 'ACTIVE_HUNT_EXISTS';end if;
  if p_latitude is not null and p_longitude is not null and p_accuracy_m is not null then
    if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 or p_accuracy_m<0 then raise exception 'GPS_REQUIRED';end if;
    if p_accuracy_m>250 then raise exception 'GPS_INACCURATE';end if;
    insert into public.player_presence(player_id,latitude,longitude,accuracy_m,is_background,updated_at)
    values(uid,p_latitude,p_longitude,p_accuracy_m,false,now())
    on conflict(player_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,accuracy_m=excluded.accuracy_m,is_background=false,updated_at=now();
  end if;
  select * into presence from public.player_presence where player_id=uid and updated_at>now()-interval '2 minutes';
  if not found then raise exception 'GPS_REQUIRED';end if;
  needed:=case when p_length_km<=2 then 3 when p_length_km<=4 then 4 when p_length_km<=6 then 5 when p_length_km<=8 then 6 else 7 end;
  cost:=25+25*p_length_km;
  update public.profiles set bone_count=bone_count-cost where id=uid and bone_count>=cost;if not found then raise exception 'INSUFFICIENT_BONES';end if;
  select team_id into team from public.hunt_team_members where player_id=uid;
  insert into public.treasure_hunts(id,owner_player_id,team_id,length_km,cost,xp_reward) values(hid,uid,team,p_length_km,cost,25*p_length_km);
  if team is null then insert into public.treasure_hunt_participants values(hid,uid,true,null);
  else insert into public.treasure_hunt_participants(hunt_id,player_id) select hid,player_id from public.hunt_team_members where team_id=team;end if;
  begin
    perform private.fill_treasure_checkpoints(hid,presence.latitude,presence.longitude,p_length_km,needed);
  exception when others then
    update public.profiles set bone_count=bone_count+cost where id=uid;delete from public.treasure_hunts where id=hid;raise;
  end;
  return hid;
end $$;

grant execute on function public.start_treasure_hunt(integer,jsonb,double precision,double precision,double precision) to authenticated;
