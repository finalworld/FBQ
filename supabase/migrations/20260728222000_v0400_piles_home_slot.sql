-- FBQ 0.400: atomic dirt-pile claims, private home and home slot machine.

-- The prototype RPC changed during manual setup; remove every old overload so
-- a changed return contract can be installed safely.
do $cleanup$
declare proc regprocedure;
begin
  for proc in
    select p.oid::regprocedure from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='open_dirt_pile'
  loop execute format('drop function %s cascade',proc); end loop;
end $cleanup$;

create table if not exists public.home_slot_spin_rewards (
  spin_id uuid not null references public.home_slot_spins(id) on delete cascade,
  bone_type smallint not null references public.bone_types(id),
  quantity integer not null check (quantity > 0),
  primary key(spin_id,bone_type)
);
alter table public.home_slot_spin_rewards enable row level security;
create policy own_home_spin_rewards_read on public.home_slot_spin_rewards
  for select to authenticated using (
    exists(select 1 from public.home_slot_spins s
      where s.id=spin_id and s.player_id=(select auth.uid()))
  );
grant select on public.home_slot_spin_rewards to authenticated;

create or replace function private.random_per_million()
returns integer language sql volatile set search_path=''
as $$ select floor(random()*1000000)::integer $$;

-- Normal rewards favour a meaningful upgrade over the lowest eligible type.
create or replace function private.pick_normal_pile_bone(pile_cost integer)
returns smallint language plpgsql volatile security definer set search_path=''
as $$
declare ids smallint[]; n integer; r integer:=private.random_per_million(); rank integer;
begin
  select array_agg(id order by value) into ids from public.bone_types where value>=pile_cost;
  n:=coalesce(array_length(ids,1),0);
  if n=0 then raise exception 'NO_ELIGIBLE_PILE_REWARD'; end if;
  if n=1 then return ids[1]; end if;
  -- 18% lowest, 42% second, 22% third, 11% fourth, 7% spread higher.
  rank:=case when r<180000 then 1 when r<600000 then 2 when r<820000 then 3
             when r<930000 then 4
             else 5+floor(((r-930000)::numeric/70000)*greatest(n-4,1))::integer end;
  return ids[least(greatest(rank,1),n)];
end $$;

-- Double rewards: lowest two share 50%, then 25%, 12%, 7%; upper rewards
-- share 5%, and the exact best possible type has 1% of double wins.
create or replace function private.pick_double_pile_bone(pile_cost integer)
returns smallint language plpgsql volatile security definer set search_path=''
as $$
declare ids smallint[]; n integer; r integer:=private.random_per_million(); rank integer;
begin
  select array_agg(id order by value) into ids from public.bone_types where value>=pile_cost;
  n:=coalesce(array_length(ids,1),0);
  if n=0 then raise exception 'NO_ELIGIBLE_PILE_REWARD'; end if;
  if n=1 then return ids[1]; end if;
  rank:=case
    when r<250000 then 1 when r<500000 then least(2,n)
    when r<750000 then least(3,n) when r<870000 then least(4,n)
    when r<940000 then least(5,n)
    when r<990000 then least(6+floor(((r-940000)::numeric/50000)*greatest(n-6,1))::integer,n-1)
    else n end;
  return ids[least(greatest(rank,1),n)];
end $$;

revoke all on function private.random_per_million() from public,anon,authenticated;
revoke all on function private.pick_normal_pile_bone(integer) from public,anon,authenticated;
revoke all on function private.pick_double_pile_bone(integer) from public,anon,authenticated;

create or replace function public.open_dirt_pile(p_pile_id uuid)
returns table(
  claim_id uuid, bone_type smallint, quantity smallint,
  cost integer, reward_value integer, balance bigint,
  is_double boolean
) language plpgsql security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid(); me public.player_presence%rowtype;
  pile public.dirt_piles%rowtype; tier public.pile_types%rowtype;
  selected_type smallint; unit_value integer; qty smallint:=1;
  new_balance bigint; cid uuid;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  select * into me from public.player_presence where player_id=uid;
  if not found or me.updated_at<now()-interval '15 seconds' or me.accuracy_m>30 then
    raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';
  end if;
  select * into pile from public.dirt_piles p where p.id=p_pile_id for update;
  if not found or not pile.active then
    raise exception 'PILE_ALREADY_CLAIMED' using errcode='P0001';
  end if;
  if private.distance_meters(me.latitude,me.longitude,pile.latitude,pile.longitude)>25 then
    raise exception 'PILE_OUT_OF_RANGE' using errcode='P0001';
  end if;
  select * into tier from public.pile_types where id=pile.pile_type;
  if not found or pile.cost<>tier.cost then
    raise exception 'INVALID_PILE_CONFIGURATION' using errcode='P0001';
  end if;

  -- Lock balance only after the pile lock. Every claimant uses the same order.
  select p.bone_count into new_balance from public.profiles p where p.id=uid for update;
  if new_balance<tier.cost then raise exception 'INSUFFICIENT_BONES' using errcode='P0001'; end if;

  if private.random_per_million()<tier.double_chance_per_million then
    qty:=2; selected_type:=private.pick_double_pile_bone(tier.cost);
  else
    selected_type:=private.pick_normal_pile_bone(tier.cost);
  end if;
  select value into unit_value from public.bone_types where id=selected_type;
  if unit_value<tier.cost then raise exception 'PILE_REWARD_BELOW_COST'; end if;

  update public.profiles set bone_count=bone_count-tier.cost,updated_at=now() where id=uid;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
  select uid,-tier.cost,p.bone_count,'dirt_pile_cost',pile.id from public.profiles p where p.id=uid;

  update public.profiles set bone_count=bone_count+(unit_value*qty),
    total_bones=total_bones+qty,total_piles=total_piles+1,updated_at=now() where id=uid
  returning bone_count into new_balance;
  insert into public.player_bone_collection(player_id,bone_type,lifetime_count,first_discovered_at,updated_at)
  values(uid,selected_type,qty,now(),now())
  on conflict(player_id,bone_type) do update set
    lifetime_count=public.player_bone_collection.lifetime_count+excluded.lifetime_count,
    first_discovered_at=coalesce(public.player_bone_collection.first_discovered_at,now()),
    updated_at=now();
  insert into public.pile_claims
    (pile_id,pile_generation,player_id,cost,bone_type,quantity,reward_value)
  values(pile.id,pile.generation,uid,tier.cost,selected_type,qty,unit_value*qty)
  returning id into cid;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
  values(uid,unit_value*qty,new_balance,'dirt_pile_reward',cid);
  update public.dirt_piles set active=false,claimed_at=now(),
    respawn_at=now()+(interval '5 minutes'+random()*interval '5 minutes'),updated_at=now()
  where id=pile.id;

  claim_id:=cid; bone_type:=selected_type; quantity:=qty; cost:=tier.cost;
  reward_value:=unit_value*qty; balance:=new_balance; is_double:=qty=2;
  return next;
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
  if not found or me.updated_at<now()-interval '15 seconds' or me.accuracy_m>30 then
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

-- Converts a currency payout into actual collectible bone types, preferring
-- the highest exact-value decomposition. Thus lifetime bone counts stay true.
create or replace function private.record_slot_bone_rewards(
  spin uuid, player uuid, payout integer
) returns void language plpgsql security definer set search_path=''
as $$
declare remaining integer:=payout; bt record; qty integer; collected_count integer:=0;
begin
  for bt in select id,value from public.bone_types order by value desc loop
    qty:=remaining/bt.value;
    if qty>0 then
      insert into public.home_slot_spin_rewards(spin_id,bone_type,quantity)
      values(spin,bt.id,qty);
      insert into public.player_bone_collection(player_id,bone_type,lifetime_count,first_discovered_at,updated_at)
      values(player,bt.id,qty,now(),now())
      on conflict(player_id,bone_type) do update set
        lifetime_count=public.player_bone_collection.lifetime_count+excluded.lifetime_count,
        first_discovered_at=coalesce(public.player_bone_collection.first_discovered_at,now()),updated_at=now();
      remaining:=remaining-(qty*bt.value);
      collected_count:=collected_count+qty;
    end if;
  end loop;
  if remaining<>0 then raise exception 'SLOT_REWARD_DECOMPOSITION_FAILED'; end if;
  update public.profiles set total_bones=total_bones+collected_count,updated_at=now()
  where id=player;
end $$;
revoke all on function private.record_slot_bone_rewards(uuid,uuid,integer) from public,anon,authenticated;

create or replace function public.spin_home_slot(p_client_request_id uuid, p_stake smallint)
returns table(
  spin_id uuid, multiplier numeric, payout integer,
  balance bigint, rewards jsonb
) language plpgsql security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid(); me public.player_presence%rowtype; p public.profiles%rowtype;
  previous public.home_slot_spins%rowtype; r integer; multi numeric(5,1); paid integer;
  sid uuid; new_balance bigint;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  if p_stake not in (1,2,5,10) then raise exception 'INVALID_STAKE' using errcode='22023'; end if;

  -- Idempotent retry: return the already-decided result without charging again.
  select * into previous from public.home_slot_spins s
  where s.player_id=uid and s.client_request_id=p_client_request_id;
  if found then
    spin_id:=previous.id; multiplier:=previous.multiplier; payout:=previous.payout;
    select bone_count into balance from public.profiles where id=uid;
    select coalesce(jsonb_agg(jsonb_build_object('bone_type',r.bone_type,'quantity',r.quantity)
      order by r.bone_type),'[]'::jsonb) into rewards
      from public.home_slot_spin_rewards r where r.spin_id=previous.id;
    return next; return;
  end if;

  select * into me from public.player_presence where player_id=uid;
  if not found or me.updated_at<now()-interval '15 seconds' or me.accuracy_m>30 then
    raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';
  end if;
  select * into p from public.profiles where id=uid for update;
  if p.home_lat is null or private.distance_meters(me.latitude,me.longitude,p.home_lat,p.home_lon)>50 then
    raise exception 'HOME_OUT_OF_RANGE' using errcode='P0001';
  end if;
  if p.bone_count<p_stake then raise exception 'INSUFFICIENT_BONES' using errcode='P0001'; end if;
  if exists(select 1 from public.home_slot_spins s where s.player_id=uid
            and s.created_at>clock_timestamp()-interval '5 seconds') then
    raise exception 'SLOT_RATE_LIMIT' using errcode='P0001';
  end if;

  r:=private.random_per_million();
  multi:=case when r<550000 then 0 when r<800000 then 1 when r<950000 then 2
              when r<990000 then 5 when r<999000 then 10 else 50 end;
  paid:=(p_stake*multi)::integer;
  update public.profiles set bone_count=bone_count-p_stake,updated_at=now() where id=uid;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
  select uid,-p_stake,x.bone_count,'home_slot_stake',p_client_request_id from public.profiles x where x.id=uid;
  insert into public.home_slot_spins(player_id,client_request_id,stake,multiplier,payout)
  values(uid,p_client_request_id,p_stake,multi,paid) returning id into sid;
  if paid>0 then
    update public.profiles set bone_count=bone_count+paid,updated_at=now() where id=uid
    returning bone_count into new_balance;
    perform private.record_slot_bone_rewards(sid,uid,paid);
    insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
    values(uid,paid,new_balance,'home_slot_payout',sid);
  else
    select bone_count into new_balance from public.profiles where id=uid;
  end if;
  spin_id:=sid; multiplier:=multi; payout:=paid; balance:=new_balance;
  select coalesce(jsonb_agg(jsonb_build_object('bone_type',sr.bone_type,'quantity',sr.quantity)
    order by sr.bone_type),'[]'::jsonb) into rewards
    from public.home_slot_spin_rewards sr where sr.spin_id=sid;
  return next;
end $$;

revoke execute on function public.open_dirt_pile(uuid) from public,anon;
revoke execute on function public.set_home_here() from public,anon;
revoke execute on function public.spin_home_slot(uuid,smallint) from public,anon;
grant execute on function public.open_dirt_pile(uuid) to authenticated;
grant execute on function public.set_home_here() to authenticated;
grant execute on function public.spin_home_slot(uuid,smallint) to authenticated;
