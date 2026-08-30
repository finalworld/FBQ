create or replace function public.buy_shop_item(p_poi_id uuid,p_item_id text,p_client_request_id uuid)
returns table(purchase_id uuid,item_id text,price bigint,balance bigint,already_owned boolean)
language plpgsql security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid();me public.player_presence%rowtype;poi public.game_pois%rowtype;
  shop_item public.shop_items%rowtype;prior public.shop_purchases%rowtype;
  new_balance bigint;pid uuid;entitled boolean;charged_price bigint;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  perform private.assert_active_player(uid);
  select s.* into prior from public.shop_purchases s
    where s.player_id=uid and s.client_request_id=p_client_request_id;
  if found then
    purchase_id:=prior.id;item_id:=prior.item_id;price:=prior.price;
    select p.bone_count into balance from public.profiles p where p.id=uid;
    already_owned:=true;return next;return;
  end if;
  select i.* into shop_item from public.shop_items i where i.id=p_item_id and i.active;
  if not found then raise exception 'SHOP_ITEM_NOT_FOUND' using errcode='P0001';end if;
  if exists(select 1 from public.player_items pi where pi.player_id=uid and pi.item_id=p_item_id) then
    raise exception 'ITEM_ALREADY_OWNED' using errcode='P0001';end if;
  select pp.* into me from public.player_presence pp where pp.player_id=uid;
  if not found or me.updated_at<now()-interval '90 seconds' or me.accuracy_m>30 then
    raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';end if;
  select gp.* into poi from public.game_pois gp where gp.id=p_poi_id and gp.active and gp.has_game_shop;
  if not found then raise exception 'GAME_SHOP_NOT_FOUND' using errcode='P0001';end if;
  if private.distance_meters(me.latitude,me.longitude,poi.latitude,poi.longitude)>50 then
    raise exception 'SHOP_OUT_OF_RANGE' using errcode='P0001';end if;
  select exists(select 1 from public.player_entitlements e where e.player_id=uid and e.item_id=p_item_id) into entitled;
  select p.bone_count into new_balance from public.profiles p where p.id=uid for update;
  charged_price:=case when entitled then 0 else shop_item.price end;
  if new_balance<charged_price then raise exception 'INSUFFICIENT_BONES' using errcode='P0001';end if;
  if charged_price>0 then
    update public.profiles p set bone_count=p.bone_count-charged_price,updated_at=now()
      where p.id=uid returning p.bone_count into new_balance;
  end if;
  insert into public.shop_purchases(player_id,item_id,poi_id,client_request_id,price)
    values(uid,p_item_id,p_poi_id,p_client_request_id,charged_price) returning id into pid;
  insert into public.player_items(player_id,item_id,acquisition_source)
    values(uid,p_item_id,case when entitled then 'entitlement' else 'shop' end);
  if charged_price>0 then
    insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
      values(uid,-charged_price,new_balance,'shop_purchase',pid);
  end if;
  purchase_id:=pid;item_id:=p_item_id;price:=charged_price;balance:=new_balance;
  already_owned:=false;return next;
exception when unique_violation then raise exception 'ITEM_ALREADY_OWNED' using errcode='P0001';
end $$;

revoke execute on function public.buy_shop_item(uuid,text,uuid) from public,anon;
grant execute on function public.buy_shop_item(uuid,text,uuid) to authenticated;
