-- Loose bones now remain away for five hours after collection, untouched
-- bones refresh after five hours, and system bones keep 200 m apart.

create or replace function public.collect_nearby_bones()
returns table(collection_id uuid,bone_type smallint,bone_value integer,bones_collected integer,rewarded_players integer,player_reward bigint,player_balance bigint)
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();me public.player_presence%rowtype;wb public.world_bones%rowtype;bt public.bone_types%rowtype;recipient record;membership record;cid uuid;reward_count integer;own_reward bigint:=0;collected_count integer:=0;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;perform private.assert_active_player(uid);
  select pp.* into me from public.player_presence pp where pp.player_id=uid for update;
  if not found or me.updated_at<now()-interval '45 seconds' or me.accuracy_m>75 then raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';end if;
  for wb in select w.* from public.world_bones w where w.active and private.distance_meters(me.latitude,me.longitude,w.latitude,w.longitude)<=greatest(25,least(me.accuracy_m,60)) order by w.created_at,w.id for update skip locked loop
    select b.* into bt from public.bone_types b where b.id=wb.bone_type;
    update public.world_bones w set active=false,collected_at=now(),respawn_at=now()+interval '5 hours',updated_at=now() where w.id=wb.id;
    insert into public.bone_collections(world_bone_id,world_generation,initiator_id,bone_type,bone_value) values(wb.id,wb.generation,uid,wb.bone_type,bt.value) returning id into cid;reward_count:=0;
    for recipient in select pp.player_id,private.distance_meters(pp.latitude,pp.longitude,wb.latitude,wb.longitude) distance_m from public.player_presence pp join public.profiles p on p.id=pp.player_id
      where pp.updated_at>=now()-interval '45 seconds' and pp.accuracy_m<=75 and not pp.admin_mode and not p.suspended_permanently and(p.suspended_until is null or p.suspended_until<=now()) and p.deleted_at is null
      and private.distance_meters(pp.latitude,pp.longitude,wb.latitude,wb.longitude)<=greatest(25,least(pp.accuracy_m,60)) order by pp.player_id loop
      insert into public.bone_collection_rewards(collection_id,player_id,distance_m) values(cid,recipient.player_id,recipient.distance_m) on conflict do nothing;
      if found then
        update public.profiles p set bone_count=p.bone_count+bt.value,total_bones=p.total_bones+1,updated_at=now() where p.id=recipient.player_id;
        perform private.award_xp(recipient.player_id,bt.value,'loose_bone',cid);
        insert into public.player_bone_collection(player_id,bone_type,lifetime_count,first_discovered_at,updated_at) values(recipient.player_id,wb.bone_type,1,now(),now())
          on conflict on constraint player_bone_collection_pkey do update set lifetime_count=public.player_bone_collection.lifetime_count+1,first_discovered_at=coalesce(public.player_bone_collection.first_discovered_at,now()),updated_at=now();
        insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id) select recipient.player_id,bt.value,p.bone_count,'loose_bone',cid from public.profiles p where p.id=recipient.player_id;
        for membership in select fm.flock_id from public.flock_members fm where fm.player_id=recipient.player_id order by fm.flock_id loop
          update public.flocks f set bank_balance=f.bank_balance+(bt.value::numeric/10),updated_at=now() where f.id=membership.flock_id;
          insert into public.flock_bank_ledger(flock_id,actor_id,amount,balance_after,reason,source_id) select membership.flock_id,recipient.player_id,bt.value::numeric/10,f.bank_balance,'loose_bone_bonus',cid from public.flocks f where f.id=membership.flock_id;
        end loop;reward_count:=reward_count+1;if recipient.player_id=uid then own_reward:=own_reward+bt.value;end if;
      end if;
    end loop;
    collection_id:=cid;bone_type:=wb.bone_type;bone_value:=bt.value;bones_collected:=1;rewarded_players:=reward_count;player_reward:=own_reward;
    select p.bone_count into player_balance from public.profiles p where p.id=uid;return next;collected_count:=collected_count+1;
  end loop;
  if collected_count=0 then raise exception 'NO_BONES_IN_RANGE' using errcode='P0001';end if;
end $$;

create or replace function private.ensure_close_bones(player_lat double precision,player_lon double precision)
returns void language plpgsql volatile security definer set search_path='' as $$
declare close_count integer;candidate record;created integer:=0;
begin
  select count(*) into close_count from public.world_bones b
  where b.active and b.placement_source='system' and private.distance_meters(player_lat,player_lon,b.latitude,b.longitude)<=600;
  while close_count+created<5 and created<5 loop
    select c.latitude,c.longitude into candidate from private.walkable_spawn_candidates c
    where private.distance_meters(player_lat,player_lon,c.latitude,c.longitude)<=600
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<200)
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(c.latitude,c.longitude,d.latitude,d.longitude)<100)
    order by random() limit 1;
    exit when not found;
    insert into public.world_bones(latitude,longitude,bone_type,active,placement_source,updated_at)
    values(candidate.latitude,candidate.longitude,private.random_bone_type(),true,'system',now());created:=created+1;
  end loop;
end $$;

revoke all on function private.ensure_close_bones(double precision,double precision) from public,anon,authenticated;

create or replace function private.maintain_world_bones(player_lat double precision,player_lon double precision)
returns void language plpgsql volatile security definer set search_path='' as $$
declare due_bone record;stale_bone record;candidate record;nearby_count integer;created integer:=0;replacement smallint;attempts integer;
begin
  if not pg_try_advisory_xact_lock(1179666257) then return;end if;
  for stale_bone in select id,bone_type from public.world_bones where active and placement_source='system' and updated_at<=now()-interval '5 hours' order by updated_at for update skip locked loop
    attempts:=0;loop replacement:=private.random_bone_type();attempts:=attempts+1;exit when replacement<>stale_bone.bone_type or attempts>=20;end loop;
    if replacement=stale_bone.bone_type then replacement:=case when stale_bone.bone_type=0 then 1 else 0 end;end if;
    update public.world_bones set bone_type=replacement,generation=generation+1,updated_at=now() where id=stale_bone.id;
  end loop;
  for due_bone in select id,latitude,longitude from public.world_bones where not active and placement_source='system' and respawn_at<=now() order by respawn_at for update skip locked loop
    select c.latitude,c.longitude into candidate from private.walkable_spawn_candidates c
    where private.distance_meters(due_bone.latitude,due_bone.longitude,c.latitude,c.longitude) between 200 and 1200
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<200)
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(c.latitude,c.longitude,d.latitude,d.longitude)<100)
    order by random() limit 1;
    if found then update public.world_bones set latitude=candidate.latitude,longitude=candidate.longitude,bone_type=private.random_bone_type(),active=true,respawn_at=null,collected_at=null,generation=generation+1,updated_at=now() where id=due_bone.id;end if;
  end loop;
  perform private.ensure_close_bones(player_lat,player_lon);
  select count(*) into nearby_count from public.world_bones b where b.active and b.placement_source='system' and private.distance_meters(player_lat,player_lon,b.latitude,b.longitude)<=3000;
  while nearby_count+created<100 and created<100 loop
    select c.latitude,c.longitude into candidate from private.walkable_spawn_candidates c
    where private.distance_meters(player_lat,player_lon,c.latitude,c.longitude)<=3000
      and not exists(select 1 from public.world_bones b where b.active and private.distance_meters(c.latitude,c.longitude,b.latitude,b.longitude)<200)
      and not exists(select 1 from public.dirt_piles d where d.active and private.distance_meters(c.latitude,c.longitude,d.latitude,d.longitude)<100)
    order by random() limit 1;
    exit when not found;
    insert into public.world_bones(latitude,longitude,bone_type,active,placement_source,updated_at)
    values(candidate.latitude,candidate.longitude,private.random_bone_type(),true,'system',now());created:=created+1;
  end loop;
end $$;

revoke all on function private.maintain_world_bones(double precision,double precision) from public,anon,authenticated;

-- Refresh the complete automatic world immediately. Keeping the established
-- candidate positions makes this operation atomic and fast; every bone gets a
-- new generation/type now, while future respawns use the new 200 m rule.
update public.world_bones
set bone_type=private.random_bone_type(),active=true,respawn_at=null,
    collected_at=null,generation=generation+1,updated_at=now()
where placement_source='system';
