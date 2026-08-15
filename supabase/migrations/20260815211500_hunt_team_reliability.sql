-- Make treasure-hunt starts use the exact GPS fix shown by the app and make
-- abandoned one-person teams self-healing when friends try to team up.

drop function if exists public.start_treasure_hunt(integer,jsonb);
drop function if exists public.start_treasure_hunt(integer,jsonb,double precision,double precision,double precision);
create function public.start_treasure_hunt(
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
    if p_accuracy_m>75 then raise exception 'GPS_INACCURATE';end if;
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

-- Keep already-installed APKs working until everybody has upgraded. The old
-- call uses the most recent presence written by the normal location tracker.
create function public.start_treasure_hunt(
  p_length_km integer,
  p_points jsonb default '[]'::jsonb
) returns uuid
language sql security definer set search_path='' as $$
  select public.start_treasure_hunt(p_length_km,p_points,null,null,null)
$$;

create or replace function public.create_hunt_team() returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();tid uuid:=gen_random_uuid();begin
 select team_id into tid from public.hunt_team_members where player_id=uid;
 if tid is not null then return tid;end if;
 insert into public.hunt_teams(id,leader_id) values(tid,uid);insert into public.hunt_team_members(team_id,player_id) values(tid,uid);return tid;
end $$;

create or replace function public.invite_to_hunt_team(p_player_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();tid uuid;iid uuid:=gen_random_uuid();target_team uuid;target_leader uuid;target_count integer;a public.player_presence%rowtype;b public.player_presence%rowtype;begin
 select id into tid from public.hunt_teams where leader_id=uid;if tid is null then raise exception 'NOT_TEAM_LEADER';end if;
 select m.team_id,t.leader_id into target_team,target_leader from public.hunt_team_members m join public.hunt_teams t on t.id=m.team_id where m.player_id=p_player_id;
 if target_team is not null then
   select count(*) into target_count from public.hunt_team_members where team_id=target_team;
   if target_leader=p_player_id and target_count=1 and not exists(select 1 from public.treasure_hunts where team_id=target_team and status='active') then
     delete from public.hunt_teams where id=target_team;
   else raise exception 'PLAYER_IN_TEAM';end if;
 end if;
 select * into a from public.player_presence where player_id=uid;select * into b from public.player_presence where player_id=p_player_id;
 if a.updated_at<now()-interval '2 minutes' or b.updated_at<now()-interval '2 minutes' or private.distance_meters(a.latitude,a.longitude,b.latitude,b.longitude)>200 then raise exception 'PLAYER_NOT_NEARBY';end if;
 update public.hunt_team_invites set status='declined' where invited_player_id=p_player_id and status='pending';
 insert into public.hunt_team_invites(id,team_id,invited_player_id,invited_by) values(iid,tid,p_player_id,uid);return iid;
end $$;

grant execute on function public.start_treasure_hunt(integer,jsonb),public.start_treasure_hunt(integer,jsonb,double precision,double precision,double precision),public.create_hunt_team(),public.invite_to_hunt_team(uuid) to authenticated;
