-- Fix 1: one live-position contract for physical actions, reliable presence,
-- immediate poop visibility, route-ordered treasure hunts and rich completion data.

alter table public.world_dog_poops alter column visible_at set default now();
update public.world_dog_poops set visible_at=created_at where active and visible_at>now();

drop function if exists public.list_nearby_players();
create function public.list_nearby_players()
returns table(
  player_id uuid,latitude double precision,longitude double precision,
  heading real,marker_id text,shared_flock_ids uuid[],position_age_seconds integer
) language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=auth.uid(); me public.player_presence%rowtype;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  select * into me from public.player_presence where player_presence.player_id=uid;
  if not found or me.updated_at<now()-interval '90 seconds' then return;end if;
  return query
  select pp.player_id,pp.latitude,pp.longitude,pp.heading,p.active_marker_id,
    coalesce((select array_agg(mine.flock_id order by mine.flock_id)
      from public.flock_members mine join public.flock_members theirs on theirs.flock_id=mine.flock_id
      where mine.player_id=uid and theirs.player_id=pp.player_id),'{}'::uuid[]),
    greatest(0,extract(epoch from now()-pp.updated_at)::integer)
  from public.player_presence pp join public.profiles p on p.id=pp.player_id
  where pp.player_id<>uid and pp.updated_at>=now()-interval '90 seconds'
    and pp.accuracy_m<=75 and p.deleted_at is null and not p.suspended_permanently
    and (p.suspended_until is null or p.suspended_until<=now())
    and private.distance_meters(me.latitude,me.longitude,pp.latitude,pp.longitude)<=250
  order by pp.player_id;
end $$;
grant execute on function public.list_nearby_players() to authenticated;

create or replace function private.fill_treasure_checkpoints(p_hunt uuid,p_lat float8,p_lon float8,p_km integer,p_needed integer)
returns void language plpgsql security definer set search_path='' as $$
declare r record;seq integer:=0;target_total float8:=p_km*1000.0;segment_target float8:=target_total/p_needed;
  travelled float8:=0;current_lat float8:=p_lat;current_lon float8:=p_lon;leg float8;
  chosen_lat float8[]:='{}';chosen_lon float8[]:='{}';i integer;clear boolean;selected boolean;
begin
  while seq<p_needed loop
    selected:=false;
    for r in
      select c.latitude,c.longitude,private.distance_meters(current_lat,current_lon,c.latitude,c.longitude) leg_m
      from private.walkable_spawn_candidates c
      where c.last_seen_at>now()-interval '45 days'
        and private.distance_meters(current_lat,current_lon,c.latitude,c.longitude) between greatest(70,segment_target*.55) and segment_target*1.45
        and private.distance_meters(p_lat,p_lon,c.latitude,c.longitude)<=greatest(1200,target_total)
      order by abs(private.distance_meters(current_lat,current_lon,c.latitude,c.longitude)-segment_target) limit 300
    loop
      clear:=true;
      if array_length(chosen_lat,1) is not null then for i in 1..array_length(chosen_lat,1) loop
        if private.distance_meters(chosen_lat[i],chosen_lon[i],r.latitude,r.longitude)<70 then clear:=false;exit;end if;
      end loop;end if;
      if clear then selected:=true;exit;end if;
    end loop;
    if not selected then raise exception 'NOT_ENOUGH_WALKABLE_POINTS';end if;
    leg:=r.leg_m;seq:=seq+1;travelled:=travelled+leg;
    insert into public.treasure_checkpoints(hunt_id,sequence,latitude,longitude) values(p_hunt,seq,r.latitude,r.longitude);
    chosen_lat:=array_append(chosen_lat,r.latitude);chosen_lon:=array_append(chosen_lon,r.longitude);
    current_lat:=r.latitude;current_lon:=r.longitude;
  end loop;
  if travelled<target_total*.65 or travelled>target_total*1.45 then raise exception 'NOT_ENOUGH_WALKABLE_POINTS';end if;
end $$;

drop function if exists public.claim_treasure_checkpoint(uuid);
create function public.claim_treasure_checkpoint(
  p_checkpoint_id uuid,p_latitude double precision,p_longitude double precision,p_accuracy_m real
) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();c public.treasure_checkpoints%rowtype;h public.treasure_hunts%rowtype;r record;
  done integer;total integer;frame text;frame_name text;mine_completed boolean:=false;
begin
  if uid is null then raise exception 'AUTH_REQUIRED';end if;
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then raise exception 'GPS_REQUIRED';end if;
  if p_accuracy_m<0 or p_accuracy_m>75 then raise exception 'GPS_INACCURATE';end if;
  insert into public.player_presence(player_id,latitude,longitude,accuracy_m,is_background,updated_at)
    values(uid,p_latitude,p_longitude,p_accuracy_m,false,clock_timestamp())
    on conflict(player_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,accuracy_m=excluded.accuracy_m,is_background=false,updated_at=excluded.updated_at;
  select * into c from public.treasure_checkpoints where id=p_checkpoint_id;
  if not found then raise exception 'CHECKPOINT_GONE';end if;
  select * into h from public.treasure_hunts where id=c.hunt_id and status='active';
  if not found then raise exception 'HUNT_NOT_ACTIVE';end if;
  if not exists(select 1 from public.treasure_hunt_participants where hunt_id=h.id and player_id=uid) then raise exception 'NOT_PARTICIPANT';end if;
  if exists(select 1 from public.treasure_checkpoint_progress where checkpoint_id=c.id and player_id=uid) then raise exception 'ALREADY_CLAIMED';end if;
  if private.distance_meters(p_latitude,p_longitude,c.latitude,c.longitude)>30+least(p_accuracy_m,25) then raise exception 'TOO_FAR';end if;
  for r in select hp.player_id from public.treasure_hunt_participants hp join public.player_presence pp on pp.player_id=hp.player_id
    where hp.hunt_id=h.id and hp.sharing_enabled and pp.updated_at>now()-interval '90 seconds' and pp.accuracy_m<=75
      and private.distance_meters(pp.latitude,pp.longitude,c.latitude,c.longitude)<=30+least(pp.accuracy_m,25)
  loop insert into public.treasure_checkpoint_progress(hunt_id,checkpoint_id,player_id) values(h.id,c.id,r.player_id) on conflict do nothing;end loop;
  for r in select player_id from public.treasure_hunt_participants where hunt_id=h.id loop
    select count(*) into done from public.treasure_checkpoint_progress where hunt_id=h.id and player_id=r.player_id;
    select count(*) into total from public.treasure_checkpoints where hunt_id=h.id;
    if done=total and not exists(select 1 from public.treasure_hunt_participants where hunt_id=h.id and player_id=r.player_id and completed_at is not null) then
      update public.treasure_hunt_participants set completed_at=now() where hunt_id=h.id and player_id=r.player_id;
      perform private.award_xp(r.player_id,h.xp_reward,'treasure_hunt',h.id);
      select f.id,f.name_sv into frame,frame_name from public.treasure_frames f order by random() limit 1;
      insert into public.player_treasure_frames values(r.player_id,frame,now()) on conflict do nothing;
      if r.player_id=uid then mine_completed:=true;end if;
    end if;
  end loop;
  if not exists(select 1 from public.treasure_hunt_participants where hunt_id=h.id and completed_at is null) then update public.treasure_hunts set status='completed',completed_at=now() where id=h.id;end if;
  return jsonb_build_object('claimed',true,'sequence',c.sequence,'completed',mine_completed,'xp_reward',case when mine_completed then h.xp_reward else 0 end,'frame_id',case when mine_completed then frame else null end,'frame_name',case when mine_completed then frame_name else null end);
end $$;
revoke execute on function public.claim_treasure_checkpoint(uuid,double precision,double precision,real) from public,anon;
grant execute on function public.claim_treasure_checkpoint(uuid,double precision,double precision,real) to authenticated;

create or replace function public.collect_dog_poop(
  p_poop_id uuid,p_latitude double precision,p_longitude double precision,p_accuracy_m real
) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();w public.world_dog_poops%rowtype;age interval;reward integer;
begin
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then raise exception 'GPS_REQUIRED';end if;
  if p_accuracy_m<0 or p_accuracy_m>75 then raise exception 'GPS_INACCURATE';end if;
  select * into w from public.world_dog_poops where id=p_poop_id and active and visible_at<=now() and expires_at>now() for update;
  if not found then raise exception 'POOP_GONE';end if;
  if private.distance_meters(p_latitude,p_longitude,w.latitude,w.longitude)>30+least(p_accuracy_m,25) then raise exception 'TOO_FAR';end if;
  age:=now()-w.created_at;reward:=case when age<interval '1 hour' then 1 when age<interval '3 hours' then 3 when age<interval '6 hours' then 7 when age<interval '12 hours' then 15 when age<interval '18 hours' then 30 else 50 end;
  update public.world_dog_poops set active=false,collected_by=uid,collected_at=now() where id=w.id;
  update public.profiles set poops_collected_lifetime=poops_collected_lifetime+1 where id=uid;
  update public.dogs set poops_collected_lifetime=poops_collected_lifetime+1 where id=(select active_dog_id from public.profiles where id=uid);
  perform private.award_xp(uid,reward,'dog_poop',w.id);
  insert into public.player_event_log(player_id,category,title,xp_delta,details,source_id) values(uid,'other','Plockade upp hundbajs',reward,jsonb_build_object('xp',reward),w.id);
  return jsonb_build_object('poop_id',w.id,'xp',reward);
end $$;
revoke execute on function public.collect_dog_poop(uuid,double precision,double precision,real) from public,anon;
grant execute on function public.collect_dog_poop(uuid,double precision,double precision,real) to authenticated;

create or replace function public.open_dirt_pile(p_pile_id uuid,p_latitude double precision,p_longitude double precision,p_accuracy_m real)
returns table(claim_id uuid,bone_type smallint,quantity smallint,cost integer,reward_value integer,balance bigint,is_double boolean)
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();pile public.dirt_piles%rowtype;tier public.pile_types%rowtype;selected_type smallint;unit_value integer;qty smallint:=1;new_balance bigint;cid uuid;recipient record;pile_xp integer;
begin
  if uid is null then raise exception 'AUTH_REQUIRED';end if;perform private.assert_active_player(uid);
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then raise exception 'GPS_REQUIRED';end if;
  if p_accuracy_m<0 or p_accuracy_m>75 then raise exception 'GPS_INACCURATE';end if;
  insert into public.player_presence(player_id,latitude,longitude,accuracy_m,is_background,updated_at) values(uid,p_latitude,p_longitude,p_accuracy_m,false,clock_timestamp()) on conflict(player_id) do update set latitude=excluded.latitude,longitude=excluded.longitude,accuracy_m=excluded.accuracy_m,is_background=false,updated_at=excluded.updated_at;
  select dp.* into pile from public.dirt_piles dp where dp.id=p_pile_id for update;if not found or not pile.active then raise exception 'PILE_ALREADY_CLAIMED';end if;
  if private.distance_meters(p_latitude,p_longitude,pile.latitude,pile.longitude)>30+least(p_accuracy_m,25) then raise exception 'PILE_OUT_OF_RANGE';end if;
  select pt.* into tier from public.pile_types pt where pt.id=pile.pile_type;if not found or pile.cost<>tier.cost then raise exception 'INVALID_PILE_CONFIGURATION';end if;
  select p.bone_count into new_balance from public.profiles p where p.id=uid for update;if new_balance<tier.cost then raise exception 'INSUFFICIENT_BONES';end if;
  if private.random_per_million()<tier.double_chance_per_million then qty:=2;selected_type:=private.pick_double_pile_bone(tier.cost);else selected_type:=private.pick_normal_pile_bone(tier.cost);end if;
  select bt.value into unit_value from public.bone_types bt where bt.id=selected_type;if unit_value<tier.cost then raise exception 'PILE_REWARD_BELOW_COST';end if;
  update public.profiles p set bone_count=p.bone_count-tier.cost,updated_at=now() where p.id=uid;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id) select uid,-tier.cost,p.bone_count,'dirt_pile_cost',pile.id from public.profiles p where p.id=uid;
  update public.profiles p set bone_count=p.bone_count+(unit_value*qty),total_bones=p.total_bones+qty,total_piles=p.total_piles+1,updated_at=now() where p.id=uid returning p.bone_count into new_balance;
  insert into public.player_bone_collection(player_id,bone_type,lifetime_count,first_discovered_at,updated_at) values(uid,selected_type,qty,now(),now()) on conflict on constraint player_bone_collection_pkey do update set lifetime_count=public.player_bone_collection.lifetime_count+excluded.lifetime_count,first_discovered_at=coalesce(public.player_bone_collection.first_discovered_at,now()),updated_at=now();
  insert into public.pile_claims(pile_id,pile_generation,player_id,cost,bone_type,quantity,reward_value) values(pile.id,pile.generation,uid,tier.cost,selected_type,qty,unit_value*qty) returning id into cid;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id) values(uid,unit_value*qty,new_balance,'dirt_pile_reward',cid);
  pile_xp:=case tier.cost when 10 then 5 when 25 then 10 when 50 then 20 when 100 then 40 else 100 end;
  for recipient in select pp.player_id from public.player_presence pp join public.profiles p on p.id=pp.player_id where pp.updated_at>=now()-interval '90 seconds' and pp.accuracy_m<=75 and not pp.admin_mode and p.deleted_at is null and private.distance_meters(pp.latitude,pp.longitude,pile.latitude,pile.longitude)<=30+least(pp.accuracy_m,25) loop perform private.award_xp(recipient.player_id,pile_xp,'dirt_pile',cid);end loop;
  update public.dirt_piles dp set active=false,claimed_at=now(),respawn_at=now()+(interval '5 minutes'+random()*interval '5 minutes'),updated_at=now() where dp.id=pile.id;
  claim_id:=cid;bone_type:=selected_type;quantity:=qty;cost:=tier.cost;reward_value:=unit_value*qty;balance:=new_balance;is_double:=qty=2;return next;
end $$;
revoke execute on function public.open_dirt_pile(uuid,double precision,double precision,real) from public,anon;
grant execute on function public.open_dirt_pile(uuid,double precision,double precision,real) to authenticated;
