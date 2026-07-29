create or replace function public.open_dirt_pile(p_pile_id uuid)
returns table(
  claim_id uuid,bone_type smallint,quantity smallint,cost integer,
  reward_value integer,balance bigint,is_double boolean
) language plpgsql security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid();me public.player_presence%rowtype;
  pile public.dirt_piles%rowtype;tier public.pile_types%rowtype;
  selected_type smallint;unit_value integer;qty smallint:=1;
  new_balance bigint;cid uuid;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  perform private.assert_active_player(uid);
  select pp.* into me from public.player_presence pp where pp.player_id=uid;
  if not found or me.updated_at<now()-interval '90 seconds' or me.accuracy_m>30 then
    raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';end if;
  select dp.* into pile from public.dirt_piles dp where dp.id=p_pile_id for update;
  if not found or not pile.active then raise exception 'PILE_ALREADY_CLAIMED' using errcode='P0001';end if;
  if private.distance_meters(me.latitude,me.longitude,pile.latitude,pile.longitude)>25 then
    raise exception 'PILE_OUT_OF_RANGE' using errcode='P0001';end if;
  select pt.* into tier from public.pile_types pt where pt.id=pile.pile_type;
  if not found or pile.cost<>tier.cost then raise exception 'INVALID_PILE_CONFIGURATION' using errcode='P0001';end if;
  select p.bone_count into new_balance from public.profiles p where p.id=uid for update;
  if new_balance<tier.cost then raise exception 'INSUFFICIENT_BONES' using errcode='P0001';end if;
  if private.random_per_million()<tier.double_chance_per_million then
    qty:=2;selected_type:=private.pick_double_pile_bone(tier.cost);
  else selected_type:=private.pick_normal_pile_bone(tier.cost);end if;
  select bt.value into unit_value from public.bone_types bt where bt.id=selected_type;
  if unit_value<tier.cost then raise exception 'PILE_REWARD_BELOW_COST';end if;
  update public.profiles p set bone_count=p.bone_count-tier.cost,updated_at=now() where p.id=uid;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
    select uid,-tier.cost,p.bone_count,'dirt_pile_cost',pile.id from public.profiles p where p.id=uid;
  update public.profiles p set bone_count=p.bone_count+(unit_value*qty),total_bones=p.total_bones+qty,
    total_piles=p.total_piles+1,updated_at=now() where p.id=uid returning p.bone_count into new_balance;
  insert into public.player_bone_collection(player_id,bone_type,lifetime_count,first_discovered_at,updated_at)
    values(uid,selected_type,qty,now(),now())
    on conflict on constraint player_bone_collection_pkey do update set
      lifetime_count=public.player_bone_collection.lifetime_count+excluded.lifetime_count,
      first_discovered_at=coalesce(public.player_bone_collection.first_discovered_at,now()),updated_at=now();
  insert into public.pile_claims(pile_id,pile_generation,player_id,cost,bone_type,quantity,reward_value)
    values(pile.id,pile.generation,uid,tier.cost,selected_type,qty,unit_value*qty) returning id into cid;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
    values(uid,unit_value*qty,new_balance,'dirt_pile_reward',cid);
  update public.dirt_piles dp set active=false,claimed_at=now(),
    respawn_at=now()+(interval '5 minutes'+random()*interval '5 minutes'),updated_at=now() where dp.id=pile.id;
  claim_id:=cid;bone_type:=selected_type;quantity:=qty;cost:=tier.cost;
  reward_value:=unit_value*qty;balance:=new_balance;is_double:=qty=2;return next;
end $$;

revoke execute on function public.open_dirt_pile(uuid) from public,anon;
grant execute on function public.open_dirt_pile(uuid) to authenticated;
