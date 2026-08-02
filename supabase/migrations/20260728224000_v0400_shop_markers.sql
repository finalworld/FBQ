-- FBQ 0.400: 96-marker launch catalogue, physical shop purchases and equipment.

create table if not exists public.shop_purchases (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  item_id text not null references public.shop_items(id),
  poi_id uuid not null references public.game_pois(id),
  client_request_id uuid not null,
  price bigint not null check(price>=0),
  purchased_at timestamptz not null default now(),
  unique(player_id,client_request_id),
  unique(player_id,item_id)
);

-- Explicit entitlements are configured by player UUID, never by a client-side
-- email/name check. This is how Frasse's owner receives the mythic marker free.
create table if not exists public.player_entitlements (
  player_id uuid not null references auth.users(id) on delete cascade,
  item_id text not null references public.shop_items(id),
  reason text not null,
  granted_at timestamptz not null default now(),
  primary key(player_id,item_id)
);

alter table public.shop_purchases enable row level security;
alter table public.player_entitlements enable row level security;
create policy own_shop_purchases_read on public.shop_purchases for select to authenticated
  using(player_id=(select auth.uid()));
create policy own_entitlements_read on public.player_entitlements for select to authenticated
  using(player_id=(select auth.uid()));
grant select on public.shop_purchases,public.player_entitlements to authenticated;

-- Rebuild the launch marker catalogue deterministically. Existing ownership is
-- preserved because IDs and assets remain stable across reruns.
with raw(category,subcategory,item_name,asset_name,category_order,item_order) as (
  select 'Markörer','Hundraser',x.name,'marker_breed_'||lpad(x.ord::text,2,'0'),1,x.ord
  from unnest(array[
    'Labrador','Golden retriever','Schäfer','Pudel','Tax','Beagle','Border collie',
    'Chihuahua','Fransk bulldogg','Mops','Rottweiler','Dobermann','Husky','Samojed',
    'Corgi','Shiba inu','Dalmatiner','Boxer','Cocker spaniel','Springer spaniel',
    'Cavalier','Yorkshireterrier','Jack russell','Schnauzer','Grand danois','Sankt bernhard',
    'Newfoundland','Cockapoo','Whippet','Greyhound','Akita','Australian shepherd',
    'Bichon frisé','Malteser','Blandras','Frasse'
  ]::text[]) with ordinality as x(name,ord)
  union all
  select 'Markörer','Hundleksaker',x.name,'marker_toy_'||lpad(x.ord::text,2,'0'),2,x.ord
  from unnest(array[
    'Tennisboll','Repknut','Pipanka','Frisbee','Kampleksak','Gummiring','Piggig boll',
    'Pipleksak','Aktiveringsboll','Tuggpinne','Mjukt får','Leksakskanin','Flygande disk',
    'Godisboll','Repboll','Leksakssko','Kong','Mjuk räv','Dragrep','Bollkastare'
  ]::text[]) with ordinality as x(name,ord)
  union all
  select 'Markörer','Tassar',x.name,'marker_paw_'||lpad(x.ord::text,2,'0'),3,x.ord
  from unnest(array[
    'Standardtass','Aprikostass','Turkostass','Skogstass','Sjötass','Guldtass',
    'Silvertass','Nattass','Regnbågstass','Eldtass','Istass','Kungstass'
  ]::text[]) with ordinality as x(name,ord)
  union all
  select 'Markörer','Halsband och namnbrickor',x.name,'marker_tag_'||lpad(x.ord::text,2,'0'),4,x.ord
  from unnest(array[
    'Rund namnbricka','Hjärtnamnbricka','Bennamnbricka','Stjärnnamnbricka','Turkost halsband',
    'Rött halsband','Kungligt halsband','Reflexhalsband','Blomhalsband','Äventyrshalsband'
  ]::text[]) with ordinality as x(name,ord)
  union all
  select 'Markörer','Koppel och utrustning',x.name,'marker_gear_'||lpad(x.ord::text,2,'0'),5,x.ord
  from unnest(array[
    'Rullkoppel','Rep-koppel','Turkos sele','Vandringssele','Hundryggsäck','Vattenflaska',
    'Bajspåsehållare','Reflexväst'
  ]::text[]) with ordinality as x(name,ord)
  union all
  select 'Markörer','Emblem och övrigt',x.name,'marker_emblem_'||lpad(x.ord::text,2,'0'),6,x.ord
  from unnest(array[
    'Tassköld','Hundkoja','Matskål','Hundkrona','Promenadstövel','Kompassben',
    'Skogsemblem','Sjöemblem','Månemblem','Sol-emblem'
  ]::text[]) with ordinality as x(name,ord)
), identified as (
  select case
      when subcategory='Tassar' and item_order=1 then 'marker_default_paw'
      when item_name='Frasse' then 'marker_frasse_mythic'
      else asset_name end as id,
    category,subcategory,item_name,
    case when subcategory='Tassar' and item_order=1 then 'marker_default_paw'
         when item_name='Frasse' then 'marker_frasse_mythic'
         else asset_name end as asset_name,
    category_order,item_order
  from raw
), ranked as (
  select i.*,row_number() over(order by category_order,item_order) as display_order,
    case when id not in ('marker_default_paw','marker_frasse_mythic') then
      row_number() over(partition by (id in ('marker_default_paw','marker_frasse_mythic'))
                        order by category_order,item_order) end as price_rank
  from identified i
), priced as (
  select *,case
    when id='marker_default_paw' then 'free'
    when id='marker_frasse_mythic' then 'mythic'
    when price_rank<=30 then 'common'
    when price_rank<=54 then 'uncommon'
    when price_rank<=72 then 'rare'
    when price_rank<=86 then 'epic'
    else 'legendary' end as rarity,
    case
    when id='marker_default_paw' then 0 when id='marker_frasse_mythic' then 10000
    when price_rank<=30 then 50 when price_rank<=54 then 150
    when price_rank<=72 then 500 when price_rank<=86 then 1500 else 5000 end as price
  from ranked
)
insert into public.shop_items
  (id,name_sv,main_category,subcategory,rarity,price,asset_name,sort_order,active,is_default)
select id,item_name,category,subcategory,rarity,price,asset_name,display_order,true,
  id='marker_default_paw' from priced
on conflict(id) do update set name_sv=excluded.name_sv,main_category=excluded.main_category,
  subcategory=excluded.subcategory,rarity=excluded.rarity,price=excluded.price,
  asset_name=excluded.asset_name,sort_order=excluded.sort_order,active=true,
  is_default=excluded.is_default;

create index if not exists shop_items_category_sort_idx
  on public.shop_items(main_category,subcategory,sort_order) where active;
create index if not exists shop_purchases_player_time_idx
  on public.shop_purchases(player_id,purchased_at desc);

create or replace function public.get_shop_catalog()
returns table(
  item_id text,name_sv text,main_category text,subcategory text,rarity text,
  price bigint,asset_name text,sort_order integer,owned boolean,equipped boolean
) language sql stable security definer set search_path=''
as $$
  select i.id,i.name_sv,i.main_category,i.subcategory,i.rarity,i.price,
    i.asset_name,i.sort_order,
    exists(select 1 from public.player_items pi where pi.player_id=auth.uid() and pi.item_id=i.id),
    exists(select 1 from public.profiles p where p.id=auth.uid() and p.active_marker_id=i.id)
  from public.shop_items i where i.active order by i.sort_order,i.id
$$;

create or replace function public.buy_shop_item(
  p_poi_id uuid,p_item_id text,p_client_request_id uuid
) returns table(purchase_id uuid,item_id text,price bigint,balance bigint,already_owned boolean)
language plpgsql security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid(); me public.player_presence%rowtype; poi public.game_pois%rowtype;
  item public.shop_items%rowtype; prior public.shop_purchases%rowtype;
  new_balance bigint; pid uuid; entitled boolean;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);

  select * into prior from public.shop_purchases s
  where s.player_id=uid and s.client_request_id=p_client_request_id;
  if found then
    purchase_id:=prior.id; item_id:=prior.item_id; price:=prior.price;
    select bone_count into balance from public.profiles where id=uid;
    already_owned:=true; return next; return;
  end if;
  select * into item from public.shop_items i where i.id=p_item_id and i.active;
  if not found then raise exception 'SHOP_ITEM_NOT_FOUND' using errcode='P0001'; end if;
  if exists(select 1 from public.player_items where player_id=uid and item_id=p_item_id) then
    raise exception 'ITEM_ALREADY_OWNED' using errcode='P0001';
  end if;
  select * into me from public.player_presence where player_id=uid;
  if not found or me.updated_at<now()-interval '15 seconds' or me.accuracy_m>30 then
    raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';
  end if;
  select * into poi from public.game_pois p where p.id=p_poi_id and p.active and p.has_game_shop;
  if not found then raise exception 'GAME_SHOP_NOT_FOUND' using errcode='P0001'; end if;
  if private.distance_meters(me.latitude,me.longitude,poi.latitude,poi.longitude)>50 then
    raise exception 'SHOP_OUT_OF_RANGE' using errcode='P0001';
  end if;

  select exists(select 1 from public.player_entitlements e
    where e.player_id=uid and e.item_id=p_item_id) into entitled;
  select p.bone_count into new_balance from public.profiles p where p.id=uid for update;
  price:=case when entitled then 0 else item.price end;
  if new_balance<price then raise exception 'INSUFFICIENT_BONES' using errcode='P0001'; end if;
  if price>0 then
    update public.profiles set bone_count=bone_count-price,updated_at=now() where id=uid
    returning bone_count into new_balance;
  end if;
  insert into public.shop_purchases(player_id,item_id,poi_id,client_request_id,price)
  values(uid,p_item_id,p_poi_id,p_client_request_id,price) returning id into pid;
  insert into public.player_items(player_id,item_id,acquisition_source)
  values(uid,p_item_id,case when entitled then 'entitlement' else 'shop' end);
  if price>0 then
    insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
    values(uid,-price,new_balance,'shop_purchase',pid);
  end if;
  purchase_id:=pid; item_id:=p_item_id; balance:=new_balance;
  already_owned:=false; return next;
exception when unique_violation then
  -- Concurrent duplicate requests roll back completely and become a safe retry.
  raise exception 'ITEM_ALREADY_OWNED' using errcode='P0001';
end $$;

create or replace function public.equip_marker(p_item_id text)
returns text language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  if not exists(select 1 from public.player_items pi join public.shop_items i on i.id=pi.item_id
    where pi.player_id=uid and pi.item_id=p_item_id and i.active and i.main_category='Markörer') then
    raise exception 'MARKER_NOT_OWNED' using errcode='42501';
  end if;
  update public.profiles set active_marker_id=p_item_id,updated_at=now() where id=uid;
  return p_item_id;
end $$;

revoke execute on function public.get_shop_catalog() from public,anon;
revoke execute on function public.buy_shop_item(uuid,text,uuid) from public,anon;
revoke execute on function public.equip_marker(text) from public,anon;
grant execute on function public.get_shop_catalog() to authenticated;
grant execute on function public.buy_shop_item(uuid,text,uuid) to authenticated;
grant execute on function public.equip_marker(text) to authenticated;
