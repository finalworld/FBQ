-- FBQ 0.500-test.19: hundbajs och Frasses skattjakt v1.
create extension if not exists pgcrypto;

alter table public.dogs add column if not exists poop_meter_remainder integer not null default 0;
alter table public.dogs add column if not exists poop_day date;
alter table public.dogs add column if not exists poop_count_today smallint not null default 0;
alter table public.dogs add column if not exists poops_created_lifetime bigint not null default 0;
alter table public.dogs add column if not exists poops_collected_lifetime bigint not null default 0;
alter table public.profiles add column if not exists poops_collected_lifetime bigint not null default 0;

create table if not exists public.world_dog_poops(
  id uuid primary key default gen_random_uuid(),
  owner_player_id uuid not null references auth.users(id) on delete cascade,
  dog_id uuid not null references public.dogs(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  created_at timestamptz not null default now(),
  visible_at timestamptz not null default now()+interval '10 minutes',
  expires_at timestamptz not null default now()+interval '24 hours',
  collected_by uuid references auth.users(id) on delete set null,
  collected_at timestamptz,
  active boolean not null default true
);
create index if not exists world_dog_poops_map on public.world_dog_poops(active,visible_at,expires_at);
alter table public.world_dog_poops enable row level security;
drop policy if exists visible_poops_read on public.world_dog_poops;
create policy visible_poops_read on public.world_dog_poops for select to authenticated
  using(active and visible_at<=now() and expires_at>now());
revoke insert,update,delete on public.world_dog_poops from anon,authenticated;

create or replace function private.spawn_dog_poops_from_walk() returns trigger
language plpgsql security definer set search_path='' as $$
declare d public.dogs%rowtype; p public.player_presence%rowtype; units integer; i integer; today_count integer;
begin
  select * into d from public.dogs where player_id=new.player_id and is_active for update;
  if not found then return new; end if;
  if d.poop_day is distinct from current_date then d.poop_day:=current_date;d.poop_count_today:=0; end if;
  units:=floor((d.poop_meter_remainder+new.meters)/100.0);
  d.poop_meter_remainder:=mod(d.poop_meter_remainder+new.meters::integer,100);
  today_count:=d.poop_count_today;
  select * into p from public.player_presence where player_id=new.player_id;
  if p.updated_at>=now()-interval '2 minutes' and p.accuracy_m<=75 then
    for i in 1..least(units,20) loop
      exit when today_count>=10;
      if random()<0.075 then
        insert into public.world_dog_poops(owner_player_id,dog_id,latitude,longitude)
        values(new.player_id,d.id,p.latitude,p.longitude);
        today_count:=today_count+1;
      end if;
    end loop;
  end if;
  update public.dogs set poop_meter_remainder=d.poop_meter_remainder,poop_day=current_date,
    poop_count_today=today_count,
    poops_created_lifetime=poops_created_lifetime+(today_count-d.poop_count_today),updated_at=now() where id=d.id;
  return new;
end $$;
drop trigger if exists spawn_dog_poops_from_walk on public.distance_batches;
create trigger spawn_dog_poops_from_walk after insert on public.distance_batches for each row execute function private.spawn_dog_poops_from_walk();

create or replace function public.collect_dog_poop(p_poop_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();w public.world_dog_poops%rowtype;p public.player_presence%rowtype;age interval;reward integer;
begin
  select * into p from public.player_presence where player_id=uid;
  if p.updated_at<now()-interval '90 seconds' or p.accuracy_m>75 then raise exception 'GPS_REQUIRED';end if;
  select * into w from public.world_dog_poops where id=p_poop_id and active and visible_at<=now() and expires_at>now() for update;
  if not found then raise exception 'POOP_GONE';end if;
  if private.distance_meters(p.latitude,p.longitude,w.latitude,w.longitude)>30+least(p.accuracy_m,20) then raise exception 'TOO_FAR';end if;
  age:=now()-w.created_at;
  reward:=case when age<interval '1 hour' then 1 when age<interval '3 hours' then 3 when age<interval '6 hours' then 7 when age<interval '12 hours' then 15 when age<interval '18 hours' then 30 else 50 end;
  update public.world_dog_poops set active=false,collected_by=uid,collected_at=now() where id=w.id;
  update public.profiles set poops_collected_lifetime=poops_collected_lifetime+1 where id=uid;
  update public.dogs set poops_collected_lifetime=poops_collected_lifetime+1 where id=(select active_dog_id from public.profiles where id=uid);
  perform private.award_xp(uid,reward,'dog_poop',w.id);
  insert into public.player_event_log(player_id,category,title,xp_delta,details,source_id)
    values(uid,'other','Plockade upp hundbajs',reward,jsonb_build_object('xp',reward),w.id);
  return jsonb_build_object('poop_id',w.id,'xp',reward);
end $$;

create table if not exists public.hunt_teams(
  id uuid primary key default gen_random_uuid(), leader_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.hunt_team_members(
  team_id uuid not null references public.hunt_teams(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),primary key(team_id,player_id),unique(player_id)
);
create table if not exists public.hunt_team_invites(
  id uuid primary key default gen_random_uuid(),team_id uuid not null references public.hunt_teams(id) on delete cascade,
  invited_player_id uuid not null references auth.users(id) on delete cascade,invited_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check(status in('pending','accepted','declined')),created_at timestamptz not null default now()
);
create table if not exists public.treasure_hunts(
  id uuid primary key default gen_random_uuid(),owner_player_id uuid not null references auth.users(id) on delete cascade,
  team_id uuid references public.hunt_teams(id) on delete set null,length_km smallint not null check(length_km between 1 and 10),
  cost integer not null,xp_reward integer not null,status text not null default 'active' check(status in('active','completed','aborted')),
  started_at timestamptz not null default now(),completed_at timestamptz
);
create unique index if not exists one_active_hunt_per_player on public.treasure_hunts(owner_player_id) where status='active';
create table if not exists public.treasure_hunt_participants(
  hunt_id uuid not null references public.treasure_hunts(id) on delete cascade,player_id uuid not null references auth.users(id) on delete cascade,
  sharing_enabled boolean not null default true,completed_at timestamptz,primary key(hunt_id,player_id)
);
create table if not exists public.treasure_checkpoints(
  id uuid primary key default gen_random_uuid(),hunt_id uuid not null references public.treasure_hunts(id) on delete cascade,
  sequence smallint not null,latitude double precision not null,longitude double precision not null,unique(hunt_id,sequence)
);
create table if not exists public.treasure_checkpoint_progress(
  hunt_id uuid not null references public.treasure_hunts(id) on delete cascade,checkpoint_id uuid not null references public.treasure_checkpoints(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,claimed_at timestamptz not null default now(),primary key(checkpoint_id,player_id)
);
create table if not exists public.treasure_frames(
  id text primary key,name_sv text not null
);
insert into public.treasure_frames values('hunt_leaf_gold','Gyllene löv'),('hunt_rune_blue','Blå runor'),('hunt_paw_vine','Svansrankan') on conflict do nothing;
create table if not exists public.player_treasure_frames(player_id uuid references auth.users(id) on delete cascade,frame_id text references public.treasure_frames(id),earned_at timestamptz default now(),primary key(player_id,frame_id));

alter table public.hunt_teams enable row level security;alter table public.hunt_team_members enable row level security;alter table public.hunt_team_invites enable row level security;
alter table public.treasure_hunts enable row level security;alter table public.treasure_hunt_participants enable row level security;alter table public.treasure_checkpoints enable row level security;alter table public.treasure_checkpoint_progress enable row level security;alter table public.player_treasure_frames enable row level security;
create or replace function private.is_hunt_team_member(p_team_id uuid,p_player_id uuid default auth.uid()) returns boolean
language sql stable security definer set search_path='' as $$select exists(select 1 from public.hunt_team_members m where m.team_id=p_team_id and m.player_id=p_player_id)$$;
create or replace function private.is_treasure_hunt_participant(p_hunt_id uuid,p_player_id uuid default auth.uid()) returns boolean
language sql stable security definer set search_path='' as $$select exists(select 1 from public.treasure_hunt_participants p where p.hunt_id=p_hunt_id and p.player_id=p_player_id)$$;
revoke all on function private.is_hunt_team_member(uuid,uuid),private.is_treasure_hunt_participant(uuid,uuid) from public;
grant execute on function private.is_hunt_team_member(uuid,uuid),private.is_treasure_hunt_participant(uuid,uuid) to authenticated;
create policy hunt_team_member_read on public.hunt_teams for select to authenticated using(private.is_hunt_team_member(id));
create policy hunt_members_read on public.hunt_team_members for select to authenticated using(private.is_hunt_team_member(team_id));
create policy hunt_invites_read on public.hunt_team_invites for select to authenticated using(invited_player_id=auth.uid() or invited_by=auth.uid());
create policy hunts_read on public.treasure_hunts for select to authenticated using(private.is_treasure_hunt_participant(id));
create policy hunt_participants_read on public.treasure_hunt_participants for select to authenticated using(private.is_treasure_hunt_participant(hunt_id));
create policy checkpoints_read on public.treasure_checkpoints for select to authenticated using(private.is_treasure_hunt_participant(hunt_id));
create policy progress_read on public.treasure_checkpoint_progress for select to authenticated using(private.is_treasure_hunt_participant(hunt_id));
create policy frames_owner_read on public.player_treasure_frames for select to authenticated using(player_id=auth.uid());
revoke insert,update,delete on public.hunt_teams,public.hunt_team_members,public.hunt_team_invites,public.treasure_hunts,public.treasure_hunt_participants,public.treasure_checkpoints,public.treasure_checkpoint_progress,public.player_treasure_frames from anon,authenticated;

create or replace function public.start_treasure_hunt(p_length_km integer,p_points jsonb default '[]'::jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();hid uuid:=gen_random_uuid();team uuid;point jsonb;seq integer:=0;needed integer;cost integer;presence public.player_presence%rowtype;generated_points jsonb:='[]'::jsonb;angle float8;radius_m float8;
begin
  if p_length_km not between 1 and 10 then raise exception 'INVALID_LENGTH';end if;
  needed:=case when p_length_km<=2 then 3 when p_length_km<=4 then 4 when p_length_km<=6 then 5 when p_length_km<=8 then 6 else 7 end;
  if coalesce(jsonb_array_length(p_points),0)=0 then
    select * into presence from public.player_presence where player_id=uid and updated_at>now()-interval '2 minutes';
    if not found then raise exception 'GPS_REQUIRED';end if;
    radius_m:=greatest(140.0,(p_length_km*1000.0)/(2*pi()));
    for seq in 1..needed loop
      angle:=2*pi()*(seq-1)/needed;
      generated_points:=generated_points||jsonb_build_array(jsonb_build_object(
        'latitude',presence.latitude+(radius_m*cos(angle))/111320.0,
        'longitude',presence.longitude+(radius_m*sin(angle))/(111320.0*cos(radians(presence.latitude)))
      ));
    end loop;
    p_points:=generated_points;seq:=0;
  end if;
  if jsonb_array_length(p_points)<>needed then raise exception 'INVALID_CHECKPOINTS';end if;
  cost:=25+25*p_length_km;
  update public.profiles set bone_count=bone_count-cost where id=uid and bone_count>=cost;if not found then raise exception 'INSUFFICIENT_BONES';end if;
  select team_id into team from public.hunt_team_members where player_id=uid;
  insert into public.treasure_hunts(id,owner_player_id,team_id,length_km,cost,xp_reward) values(hid,uid,team,p_length_km,cost,25*p_length_km);
  if team is null then insert into public.treasure_hunt_participants values(hid,uid,true,null);
  else insert into public.treasure_hunt_participants(hunt_id,player_id) select hid,player_id from public.hunt_team_members where team_id=team;end if;
  for point in select * from jsonb_array_elements(p_points) loop seq:=seq+1;insert into public.treasure_checkpoints(hunt_id,sequence,latitude,longitude) values(hid,seq,(point->>'latitude')::float8,(point->>'longitude')::float8);end loop;
  return hid;
end $$;

create or replace function public.claim_treasure_checkpoint(p_checkpoint_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();c public.treasure_checkpoints%rowtype;p public.player_presence%rowtype;h public.treasure_hunts%rowtype;r record;done integer;total integer;frame text;
begin
  select * into p from public.player_presence where player_id=uid;if p.updated_at<now()-interval '90 seconds' or p.accuracy_m>75 then raise exception 'GPS_REQUIRED';end if;
  select * into c from public.treasure_checkpoints where id=p_checkpoint_id;select * into h from public.treasure_hunts where id=c.hunt_id and status='active';
  if not exists(select 1 from public.treasure_hunt_participants where hunt_id=h.id and player_id=uid) then raise exception 'NOT_PARTICIPANT';end if;
  if private.distance_meters(p.latitude,p.longitude,c.latitude,c.longitude)>30+least(p.accuracy_m,20) then raise exception 'TOO_FAR';end if;
  for r in select hp.player_id from public.treasure_hunt_participants hp join public.player_presence pp on pp.player_id=hp.player_id where hp.hunt_id=h.id and hp.sharing_enabled and pp.updated_at>now()-interval '90 seconds' and private.distance_meters(pp.latitude,pp.longitude,c.latitude,c.longitude)<=30+least(pp.accuracy_m,20) loop
    insert into public.treasure_checkpoint_progress(hunt_id,checkpoint_id,player_id) values(h.id,c.id,r.player_id) on conflict do nothing;
  end loop;
  for r in select player_id from public.treasure_hunt_participants where hunt_id=h.id loop
    select count(*) into done from public.treasure_checkpoint_progress where hunt_id=h.id and player_id=r.player_id;select count(*) into total from public.treasure_checkpoints where hunt_id=h.id;
    if done=total and not exists(select 1 from public.treasure_hunt_participants where hunt_id=h.id and player_id=r.player_id and completed_at is not null) then
      update public.treasure_hunt_participants set completed_at=now() where hunt_id=h.id and player_id=r.player_id;perform private.award_xp(r.player_id,h.xp_reward,'treasure_hunt',h.id);
      select id into frame from public.treasure_frames order by random() limit 1;insert into public.player_treasure_frames values(r.player_id,frame,now()) on conflict do nothing;
    end if;
  end loop;
  if not exists(select 1 from public.treasure_hunt_participants where hunt_id=h.id and completed_at is null) then update public.treasure_hunts set status='completed',completed_at=now() where id=h.id;end if;
  return jsonb_build_object('claimed',true,'sequence',c.sequence);
end $$;

create or replace function public.abort_treasure_hunt() returns void language plpgsql security definer set search_path='' as $$
begin
  update public.treasure_hunts set status='aborted' where owner_player_id=auth.uid() and status='active';
end $$;
create or replace function public.get_treasure_hunt_state() returns jsonb language sql stable security definer set search_path='' as $$
select coalesce((select jsonb_build_object('active',true,'id',h.id,'length_km',h.length_km,'cost',h.cost,'xp_reward',h.xp_reward,'owner_player_id',h.owner_player_id,'checkpoints',(select jsonb_agg(jsonb_build_object('id',c.id,'sequence',c.sequence,'latitude',c.latitude,'longitude',c.longitude,'claimed',exists(select 1 from public.treasure_checkpoint_progress p where p.checkpoint_id=c.id and p.player_id=auth.uid())) order by c.sequence) from public.treasure_checkpoints c where c.hunt_id=h.id)) from public.treasure_hunts h join public.treasure_hunt_participants hp on hp.hunt_id=h.id where hp.player_id=auth.uid() and h.status='active' order by h.started_at desc limit 1),jsonb_build_object('active',false,'checkpoints','[]'::jsonb)) $$;

do $$ begin begin alter publication supabase_realtime add table public.world_dog_poops;exception when duplicate_object then null;end;begin alter publication supabase_realtime add table public.treasure_checkpoint_progress;exception when duplicate_object then null;end;end $$;
grant select on public.world_dog_poops,public.hunt_teams,public.hunt_team_members,public.hunt_team_invites,public.treasure_hunts,public.treasure_hunt_participants,public.treasure_checkpoints,public.treasure_checkpoint_progress,public.treasure_frames,public.player_treasure_frames to authenticated;
grant execute on function public.collect_dog_poop(uuid),public.start_treasure_hunt(integer,jsonb),public.claim_treasure_checkpoint(uuid),public.abort_treasure_hunt(),public.get_treasure_hunt_state() to authenticated;

-- Complete jaktlag/reroll implementation and anchor generated checkpoints to
-- the walkable OSM candidates already synced by the Android client.
create or replace function private.fill_treasure_checkpoints(p_hunt uuid,p_lat float8,p_lon float8,p_km integer,p_needed integer) returns void
language plpgsql security definer set search_path='' as $$
declare r record; seq integer:=0; max_radius float8:=greatest(650,p_km*650); min_gap float8:=greatest(100,p_km*25); chosen_lat float8[]:='{}'; chosen_lon float8[]:='{}'; ok boolean; i integer;
begin
  for r in select latitude,longitude from private.walkable_spawn_candidates
    where last_seen_at>now()-interval '45 days'
      and private.distance_meters(p_lat,p_lon,latitude,longitude) between 90 and max_radius
    order by random() limit 1200
  loop
    ok:=true;
    if array_length(chosen_lat,1) is not null then
      for i in 1..array_length(chosen_lat,1) loop
        if private.distance_meters(chosen_lat[i],chosen_lon[i],r.latitude,r.longitude)<min_gap then ok:=false;exit;end if;
      end loop;
    end if;
    if ok then
      seq:=seq+1;chosen_lat:=array_append(chosen_lat,r.latitude);chosen_lon:=array_append(chosen_lon,r.longitude);
      insert into public.treasure_checkpoints(hunt_id,sequence,latitude,longitude) values(p_hunt,seq,r.latitude,r.longitude);
      exit when seq=p_needed;
    end if;
  end loop;
  if seq<p_needed then raise exception 'NOT_ENOUGH_WALKABLE_POINTS';end if;
end $$;

create or replace function public.start_treasure_hunt(p_length_km integer,p_points jsonb default '[]'::jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();hid uuid:=gen_random_uuid();team uuid;needed integer;cost integer;presence public.player_presence%rowtype;
begin
  if p_length_km not between 1 and 10 then raise exception 'INVALID_LENGTH';end if;
  if exists(select 1 from public.treasure_hunt_participants hp join public.treasure_hunts h on h.id=hp.hunt_id where hp.player_id=uid and h.status='active') then raise exception 'ACTIVE_HUNT_EXISTS';end if;
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

create or replace function public.reroll_treasure_hunt() returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();h public.treasure_hunts%rowtype;p public.player_presence%rowtype;needed integer;
begin
 select h0.* into h from public.treasure_hunts h0 where h0.owner_player_id=uid and h0.status='active' for update;
 if not found then raise exception 'NO_ACTIVE_HUNT';end if;
 if exists(select 1 from public.treasure_checkpoint_progress where hunt_id=h.id) then raise exception 'REROLL_LOCKED';end if;
 select * into p from public.player_presence where player_id=uid and updated_at>now()-interval '2 minutes';if not found then raise exception 'GPS_REQUIRED';end if;
 needed:=case when h.length_km<=2 then 3 when h.length_km<=4 then 4 when h.length_km<=6 then 5 when h.length_km<=8 then 6 else 7 end;
 delete from public.treasure_checkpoints where hunt_id=h.id;perform private.fill_treasure_checkpoints(h.id,p.latitude,p.longitude,h.length_km,needed);return h.id;
end $$;

create or replace function public.create_hunt_team() returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();tid uuid:=gen_random_uuid();begin
 if exists(select 1 from public.hunt_team_members where player_id=uid) then raise exception 'ALREADY_IN_TEAM';end if;
 insert into public.hunt_teams(id,leader_id) values(tid,uid);insert into public.hunt_team_members(team_id,player_id) values(tid,uid);return tid;
end $$;

create or replace function public.invite_to_hunt_team(p_player_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();tid uuid;iid uuid:=gen_random_uuid();a public.player_presence%rowtype;b public.player_presence%rowtype;begin
 select id into tid from public.hunt_teams where leader_id=uid;if tid is null then raise exception 'NOT_TEAM_LEADER';end if;
 if exists(select 1 from public.hunt_team_members where player_id=p_player_id) then raise exception 'PLAYER_IN_TEAM';end if;
 select * into a from public.player_presence where player_id=uid;select * into b from public.player_presence where player_id=p_player_id;
 if a.updated_at<now()-interval '2 minutes' or b.updated_at<now()-interval '2 minutes' or private.distance_meters(a.latitude,a.longitude,b.latitude,b.longitude)>200 then raise exception 'PLAYER_NOT_NEARBY';end if;
 update public.hunt_team_invites set status='declined' where invited_player_id=p_player_id and status='pending';
 insert into public.hunt_team_invites(id,team_id,invited_player_id,invited_by) values(iid,tid,p_player_id,uid);return iid;
end $$;

create or replace function public.respond_hunt_team_invite(p_invite_id uuid,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();i public.hunt_team_invites%rowtype;begin
 select * into i from public.hunt_team_invites where id=p_invite_id and invited_player_id=uid and status='pending' for update;if not found then raise exception 'INVITE_NOT_FOUND';end if;
 if p_accept then if exists(select 1 from public.hunt_team_members where player_id=uid) then raise exception 'ALREADY_IN_TEAM';end if;insert into public.hunt_team_members(team_id,player_id) values(i.team_id,uid);end if;
 update public.hunt_team_invites set status=case when p_accept then 'accepted' else 'declined' end where id=i.id;
end $$;

create or replace function public.leave_hunt_team() returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();tid uuid;leader uuid;begin
 select m.team_id,t.leader_id into tid,leader from public.hunt_team_members m join public.hunt_teams t on t.id=m.team_id where m.player_id=uid;if tid is null then return;end if;
 update public.treasure_hunt_participants hp set sharing_enabled=false from public.treasure_hunts h where h.id=hp.hunt_id and h.team_id=tid and (hp.player_id=uid or leader=uid);
 if leader=uid then delete from public.hunt_teams where id=tid;else delete from public.hunt_team_members where team_id=tid and player_id=uid;end if;
end $$;

create or replace function public.kick_hunt_team_member(p_player_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();tid uuid;begin
 select id into tid from public.hunt_teams where leader_id=uid;if tid is null or p_player_id=uid then raise exception 'NOT_ALLOWED';end if;
 update public.treasure_hunt_participants hp set sharing_enabled=false from public.treasure_hunts h where h.id=hp.hunt_id and h.team_id=tid and hp.player_id=p_player_id;
 delete from public.hunt_team_members where team_id=tid and player_id=p_player_id;
end $$;

create or replace function public.get_hunt_team_state() returns jsonb language sql stable security definer set search_path='' as $$
with mine as(select m.team_id,t.leader_id from public.hunt_team_members m join public.hunt_teams t on t.id=m.team_id where m.player_id=auth.uid()), me as(select * from public.player_presence where player_id=auth.uid())
select jsonb_build_object(
 'team_id',(select team_id from mine),'leader_id',(select leader_id from mine),'is_leader',coalesce((select leader_id=auth.uid() from mine),false),
 'members',coalesce((select jsonb_agg(jsonb_build_object('player_id',m.player_id,'display_name',p.display_name,'level',coalesce(p.player_level,1),'is_leader',m.player_id=x.leader_id) order by m.joined_at) from mine x join public.hunt_team_members m on m.team_id=x.team_id join public.profiles p on p.id=m.player_id),'[]'::jsonb),
 'invites',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'team_id',i.team_id,'leader_name',p.display_name)) from public.hunt_team_invites i join public.profiles p on p.id=i.invited_by where i.invited_player_id=auth.uid() and i.status='pending'),'[]'::jsonb),
 'nearby',coalesce((select jsonb_agg(jsonb_build_object('player_id',pp.player_id,'display_name',pr.display_name,'distance_m',round(private.distance_meters(me.latitude,me.longitude,pp.latitude,pp.longitude)))) from me join public.player_presence pp on pp.player_id<>auth.uid() and pp.updated_at>now()-interval '2 minutes' join public.profiles pr on pr.id=pp.player_id where private.distance_meters(me.latitude,me.longitude,pp.latitude,pp.longitude)<=200 and not exists(select 1 from public.hunt_team_members hm where hm.player_id=pp.player_id)),'[]'::jsonb)
) $$;

grant execute on function public.reroll_treasure_hunt(),public.create_hunt_team(),public.invite_to_hunt_team(uuid),public.respond_hunt_team_invite(uuid,boolean),public.leave_hunt_team(),public.kick_hunt_team_member(uuid),public.get_hunt_team_state() to authenticated;
