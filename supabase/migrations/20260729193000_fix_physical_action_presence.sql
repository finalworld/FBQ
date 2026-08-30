-- Physical testing showed that the client can legitimately keep its last
-- server presence for more than 15 seconds while a confirmation dialog or
-- full-screen shop is open. Keep the <=30 m accuracy and physical distance
-- checks, but allow a 90-second presence sample for piles and purchases.

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
  select * into me from public.player_presence where player_id=uid;
  if not found or me.updated_at<now()-interval '90 seconds' or me.accuracy_m>30 then
    raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';end if;
  select * into pile from public.dirt_piles p where p.id=p_pile_id for update;
  if not found or not pile.active then raise exception 'PILE_ALREADY_CLAIMED' using errcode='P0001';end if;
  if private.distance_meters(me.latitude,me.longitude,pile.latitude,pile.longitude)>25 then
    raise exception 'PILE_OUT_OF_RANGE' using errcode='P0001';end if;
  select * into tier from public.pile_types where id=pile.pile_type;
  if not found or pile.cost<>tier.cost then raise exception 'INVALID_PILE_CONFIGURATION' using errcode='P0001';end if;
  select p.bone_count into new_balance from public.profiles p where p.id=uid for update;
  if new_balance<tier.cost then raise exception 'INSUFFICIENT_BONES' using errcode='P0001';end if;
  if private.random_per_million()<tier.double_chance_per_million then
    qty:=2;selected_type:=private.pick_double_pile_bone(tier.cost);
  else selected_type:=private.pick_normal_pile_bone(tier.cost);end if;
  select value into unit_value from public.bone_types where id=selected_type;
  if unit_value<tier.cost then raise exception 'PILE_REWARD_BELOW_COST';end if;
  update public.profiles set bone_count=bone_count-tier.cost,updated_at=now() where id=uid;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
    select uid,-tier.cost,p.bone_count,'dirt_pile_cost',pile.id from public.profiles p where p.id=uid;
  update public.profiles set bone_count=bone_count+(unit_value*qty),total_bones=total_bones+qty,
    total_piles=total_piles+1,updated_at=now() where id=uid returning bone_count into new_balance;
  insert into public.player_bone_collection(player_id,bone_type,lifetime_count,first_discovered_at,updated_at)
    values(uid,selected_type,qty,now(),now()) on conflict(player_id,bone_type) do update set
    lifetime_count=public.player_bone_collection.lifetime_count+excluded.lifetime_count,
    first_discovered_at=coalesce(public.player_bone_collection.first_discovered_at,now()),updated_at=now();
  insert into public.pile_claims(pile_id,pile_generation,player_id,cost,bone_type,quantity,reward_value)
    values(pile.id,pile.generation,uid,tier.cost,selected_type,qty,unit_value*qty) returning id into cid;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
    values(uid,unit_value*qty,new_balance,'dirt_pile_reward',cid);
  update public.dirt_piles set active=false,claimed_at=now(),
    respawn_at=now()+(interval '5 minutes'+random()*interval '5 minutes'),updated_at=now() where id=pile.id;
  claim_id:=cid;bone_type:=selected_type;quantity:=qty;cost:=tier.cost;
  reward_value:=unit_value*qty;balance:=new_balance;is_double:=qty=2;return next;
end $$;

create or replace function public.buy_shop_item(p_poi_id uuid,p_item_id text,p_client_request_id uuid)
returns table(purchase_id uuid,item_id text,price bigint,balance bigint,already_owned boolean)
language plpgsql security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid();me public.player_presence%rowtype;poi public.game_pois%rowtype;
  item public.shop_items%rowtype;prior public.shop_purchases%rowtype;
  new_balance bigint;pid uuid;entitled boolean;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  perform private.assert_active_player(uid);
  select * into prior from public.shop_purchases s where s.player_id=uid and s.client_request_id=p_client_request_id;
  if found then purchase_id:=prior.id;item_id:=prior.item_id;price:=prior.price;
    select bone_count into balance from public.profiles where id=uid;already_owned:=true;return next;return;end if;
  select * into item from public.shop_items i where i.id=p_item_id and i.active;
  if not found then raise exception 'SHOP_ITEM_NOT_FOUND' using errcode='P0001';end if;
  if exists(select 1 from public.player_items where player_id=uid and item_id=p_item_id) then
    raise exception 'ITEM_ALREADY_OWNED' using errcode='P0001';end if;
  select * into me from public.player_presence where player_id=uid;
  if not found or me.updated_at<now()-interval '90 seconds' or me.accuracy_m>30 then
    raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';end if;
  select * into poi from public.game_pois p where p.id=p_poi_id and p.active and p.has_game_shop;
  if not found then raise exception 'GAME_SHOP_NOT_FOUND' using errcode='P0001';end if;
  if private.distance_meters(me.latitude,me.longitude,poi.latitude,poi.longitude)>50 then
    raise exception 'SHOP_OUT_OF_RANGE' using errcode='P0001';end if;
  select exists(select 1 from public.player_entitlements e where e.player_id=uid and e.item_id=p_item_id) into entitled;
  select p.bone_count into new_balance from public.profiles p where p.id=uid for update;
  price:=case when entitled then 0 else item.price end;
  if new_balance<price then raise exception 'INSUFFICIENT_BONES' using errcode='P0001';end if;
  if price>0 then update public.profiles set bone_count=bone_count-price,updated_at=now()
    where id=uid returning bone_count into new_balance;end if;
  insert into public.shop_purchases(player_id,item_id,poi_id,client_request_id,price)
    values(uid,p_item_id,p_poi_id,p_client_request_id,price) returning id into pid;
  insert into public.player_items(player_id,item_id,acquisition_source)
    values(uid,p_item_id,case when entitled then 'entitlement' else 'shop' end);
  if price>0 then insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
    values(uid,-price,new_balance,'shop_purchase',pid);end if;
  purchase_id:=pid;item_id:=p_item_id;balance:=new_balance;already_owned:=false;return next;
exception when unique_violation then raise exception 'ITEM_ALREADY_OWNED' using errcode='P0001';
end $$;

revoke execute on function public.open_dirt_pile(uuid) from public,anon;
revoke execute on function public.buy_shop_item(uuid,text,uuid) from public,anon;
grant execute on function public.open_dirt_pile(uuid) to authenticated;
grant execute on function public.buy_shop_item(uuid,text,uuid) to authenticated;
