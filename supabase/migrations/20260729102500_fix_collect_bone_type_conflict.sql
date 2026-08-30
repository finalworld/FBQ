-- collect_nearby_bones() returns an output column named bone_type. In
-- PL/pgSQL that name conflicted with ON CONFLICT(player_id,bone_type).
-- Naming the primary-key constraint removes the ambiguity completely.
create or replace function public.collect_nearby_bones()
returns table(
  collection_id uuid, bone_type smallint, bone_value integer,
  bones_collected integer, rewarded_players integer,
  player_reward bigint, player_balance bigint
) language plpgsql security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid(); me public.player_presence%rowtype;
  wb public.world_bones%rowtype; bt public.bone_types%rowtype;
  recipient record; membership record; cid uuid;
  reward_count integer; own_reward bigint:=0; collected_count integer:=0;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  select * into me from public.player_presence where player_id=uid for update;
  if not found or me.updated_at<now()-interval '15 seconds' or me.accuracy_m>30 then
    raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';
  end if;

  for wb in
    select w.* from public.world_bones w
    where w.active and private.distance_meters(
      me.latitude,me.longitude,w.latitude,w.longitude
    )<=25
    order by w.created_at,w.id for update skip locked
  loop
    select * into bt from public.bone_types where id=wb.bone_type;
    update public.world_bones set active=false,collected_at=now(),
      respawn_at=now()+interval '5 minutes',updated_at=now() where id=wb.id;
    insert into public.bone_collections
      (world_bone_id,world_generation,initiator_id,bone_type,bone_value)
    values(wb.id,wb.generation,uid,wb.bone_type,bt.value) returning id into cid;
    reward_count:=0;

    for recipient in
      select pp.player_id,
        private.distance_meters(
          pp.latitude,pp.longitude,wb.latitude,wb.longitude
        ) as distance_m
      from public.player_presence pp
      join public.profiles p on p.id=pp.player_id
      where pp.updated_at>=now()-interval '15 seconds' and pp.accuracy_m<=30
        and not p.suspended_permanently
        and (p.suspended_until is null or p.suspended_until<=now())
        and p.deleted_at is null
        and private.distance_meters(
          pp.latitude,pp.longitude,wb.latitude,wb.longitude
        )<=25
      order by pp.player_id
    loop
      insert into public.bone_collection_rewards(
        collection_id,player_id,distance_m
      ) values(cid,recipient.player_id,recipient.distance_m) on conflict do nothing;
      if found then
        update public.profiles set bone_count=bone_count+bt.value,
          total_bones=total_bones+1,updated_at=now()
        where id=recipient.player_id;
        insert into public.player_bone_collection
          (player_id,bone_type,lifetime_count,first_discovered_at,updated_at)
        values(recipient.player_id,wb.bone_type,1,now(),now())
        on conflict on constraint player_bone_collection_pkey do update set
          lifetime_count=public.player_bone_collection.lifetime_count+1,
          first_discovered_at=coalesce(
            public.player_bone_collection.first_discovered_at,now()
          ),updated_at=now();
        insert into public.player_bone_ledger(
          player_id,amount,balance_after,reason,source_id
        ) select recipient.player_id,bt.value,p.bone_count,'loose_bone',cid
          from public.profiles p where p.id=recipient.player_id;

        for membership in
          select fm.flock_id from public.flock_members fm
          where fm.player_id=recipient.player_id order by fm.flock_id
        loop
          update public.flocks
          set bank_balance=bank_balance+(bt.value::numeric/10),updated_at=now()
          where id=membership.flock_id;
          insert into public.flock_bank_ledger(
            flock_id,actor_id,amount,balance_after,reason,source_id
          ) select membership.flock_id,recipient.player_id,
              bt.value::numeric/10,f.bank_balance,'loose_bone_bonus',cid
            from public.flocks f where f.id=membership.flock_id;
        end loop;
        reward_count:=reward_count+1;
        if recipient.player_id=uid then own_reward:=own_reward+bt.value; end if;
      end if;
    end loop;
    collection_id:=cid; bone_type:=wb.bone_type; bone_value:=bt.value;
    bones_collected:=1; rewarded_players:=reward_count;
    player_reward:=own_reward;
    select p.bone_count into player_balance
      from public.profiles p where p.id=uid;
    return next;
    collected_count:=collected_count+1;
  end loop;
  if collected_count=0 then
    raise exception 'NO_BONES_IN_RANGE' using errcode='P0001';
  end if;
end
$$;

revoke execute on function public.collect_nearby_bones() from public,anon;
grant execute on function public.collect_nearby_bones() to authenticated;
