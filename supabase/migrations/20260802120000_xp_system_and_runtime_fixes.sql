-- FBQ XP, reliable live rewards, and ambiguity-safe economy routines.
-- Puppy/dog progression is intentionally not part of this migration.

alter table public.profiles
  add column if not exists xp_total numeric(20,2) not null default 0,
  add column if not exists xp_from_bones numeric(20,2) not null default 0,
  add column if not exists xp_from_walking numeric(20,2) not null default 0,
  add column if not exists xp_from_piles numeric(20,2) not null default 0,
  add column if not exists xp_walk_remainder_m integer not null default 0,
  add column if not exists player_level integer not null default 1,
  add column if not exists highest_level integer not null default 1,
  add column if not exists pending_level_from integer,
  add column if not exists pending_level_to integer,
  add column if not exists pending_level_bones bigint not null default 0,
  add column if not exists pending_level_notice boolean not null default false;

alter table public.player_presence add column if not exists admin_mode boolean not null default false;

update public.bone_types set name_sv=case id when 0 then 'Vanligt ben' when 1 then 'Slitet ben' when 2 then 'Jordigt ben' when 3 then 'Polerat ben' when 4 then 'Mossben' when 5 then 'Järnben' when 6 then 'Kopparben' when 7 then 'Rubinben' when 8 then 'Ametistben' when 9 then 'Iskristallben' when 10 then 'Diamantben' else 'Stjärnben' end;

-- The old catalogue order did not match the sprite atlas. Keep stable item IDs
-- and ownership, but make every visible breed/toy name describe its own cell.
with names(ord,name) as (select * from unnest(array[
  'Golden retriever','Corgi','Shiba inu','Mops','Siberian husky','Tax','Bichon frisé','Cavalier king charles spaniel','Border collie','Labrador',
  'West highland white terrier','Fransk bulldogg','Bostonterrier','Beagle','Cocker spaniel','Bullterrier','Yorkshireterrier','Shiba inu, svart','Dalmatiner','Schnauzer',
  'Shetland sheepdog','Rottweiler','Australian shepherd','Pomeranian','Sankt bernhard','Border collie, långhårig','Akita','Staffordshire bullterrier','Goldendoodle','Husky',
  'Welsh corgi','Samojed','Engelsk bulldogg','Skotsk terrier','Pudel'
]::text[]) with ordinality)
update public.shop_items i set name_sv=n.name from names n where i.id='marker_breed_'||lpad(n.ord::text,2,'0');

with names(ord,name) as (select * from unnest(array[
  'Tennisboll','Repboll','Pipanka','Frisbee','Tuggben','Mjuk bläckfisk','Gummiring','Piggig boll','Leksaksben','Mjukt får',
  'Leksakskanin','Nallebjörn','Dragrep','Mjuk val','Repknut','Aktiveringsben','Leksakssko','Godisskopa','Kong','Flätad boll'
]::text[]) with ordinality)
update public.shop_items i set name_sv=n.name from names n where i.id='marker_toy_'||lpad(n.ord::text,2,'0');

create table if not exists public.level_curve(
  level integer primary key check(level between 1 and 100),
  cumulative_xp numeric(20,2) not null unique check(cumulative_xp>=0)
);

-- Piecewise-linear first test curve. It is server data and can be balanced
-- later without publishing a new APK.
with anchors(level,xp) as (values
  (1,0),(2,25),(5,125),(10,400),(20,1500),(30,3500),(40,7000),
  (50,12500),(60,21000),(70,33000),(80,50000),(90,72000),(100,100000)
), generated as (
  select g as level, round((case when a.level=b.level then a.xp::numeric else a.xp + (b.xp-a.xp)::numeric*(g-a.level)/(b.level-a.level) end)::numeric,2) xp
  from generate_series(1,100) g
  join lateral (select * from anchors where level<=g order by level desc limit 1) a on true
  join lateral (select * from anchors where level>=g order by level limit 1) b on true
)
insert into public.level_curve(level,cumulative_xp)
select level,xp from generated
on conflict(level) do update set cumulative_xp=excluded.cumulative_xp;

create table if not exists public.player_xp_ledger(
  id bigserial primary key, player_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(20,2) not null, source text not null, source_id uuid,
  total_after numeric(20,2) not null, level_after integer not null,
  is_admin_adjustment boolean not null default false, created_at timestamptz not null default now()
);
create unique index if not exists player_xp_source_once
  on public.player_xp_ledger(player_id,source,source_id) where source_id is not null and not is_admin_adjustment;
alter table public.player_xp_ledger enable row level security;
drop policy if exists xp_ledger_own_read on public.player_xp_ledger;
create policy xp_ledger_own_read on public.player_xp_ledger for select to authenticated using(player_id=auth.uid());

create or replace function private.level_for_xp(p_xp numeric)
returns integer language sql stable set search_path='' as $$
  select coalesce(max(level),1) from public.level_curve where cumulative_xp<=greatest(p_xp,0)
$$;

create or replace function private.level_reward(p_from integer,p_to integer)
returns bigint language sql immutable set search_path='' as $$
  select coalesce(sum(l + case when l%10=0 then l*5 else 0 end + case when l=100 then 1000 else 0 end),0)::bigint
  from generate_series(p_from+1,p_to) l
$$;

create or replace function private.award_xp(p_player uuid,p_amount numeric,p_source text,p_source_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare old_level integer;new_level integer;new_total numeric;reward bigint;new_balance bigint;
begin
  if p_amount<=0 then return; end if;
  if exists(select 1 from public.player_presence pp where pp.player_id=p_player and pp.admin_mode) then return; end if;
  if p_source_id is not null and exists(select 1 from public.player_xp_ledger x where x.player_id=p_player and x.source=p_source and x.source_id=p_source_id and not x.is_admin_adjustment) then return; end if;
  select p.player_level,p.xp_total into old_level,new_total from public.profiles p where p.id=p_player for update;
  if not found then return; end if;
  new_total:=new_total+p_amount; new_level:=private.level_for_xp(new_total);
  reward:=case when new_level>old_level then private.level_reward(old_level,new_level) else 0 end;
  update public.profiles p set xp_total=new_total,player_level=greatest(p.player_level,new_level),highest_level=greatest(p.highest_level,new_level),
    xp_from_bones=p.xp_from_bones+case when p_source='loose_bone' then p_amount else 0 end,
    xp_from_walking=p.xp_from_walking+case when p_source='walking' then p_amount else 0 end,
    xp_from_piles=p.xp_from_piles+case when p_source='dirt_pile' then p_amount else 0 end,
    bone_count=p.bone_count+reward,
    pending_level_from=case when new_level>old_level then coalesce(p.pending_level_from,old_level) else p.pending_level_from end,
    pending_level_to=case when new_level>old_level then greatest(coalesce(p.pending_level_to,new_level),new_level) else p.pending_level_to end,
    pending_level_bones=p.pending_level_bones+reward,
    pending_level_notice=p.pending_level_notice or new_level>old_level,updated_at=now()
  where p.id=p_player returning p.bone_count into new_balance;
  insert into public.player_xp_ledger(player_id,amount,source,source_id,total_after,level_after)
  values(p_player,p_amount,p_source,p_source_id,new_total,new_level);
  if reward>0 then insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
    values(p_player,reward,new_balance,'level_reward',p_source_id); end if;
end $$;

-- The OUT columns changed in 0.402. PostgreSQL cannot alter a function's
-- table return type through CREATE OR REPLACE, so remove the old no-arg
-- signature first. This drops code only; no player or game data is removed.
drop function if exists public.get_session_bootstrap();
create or replace function public.get_session_bootstrap()
returns table(
  player_id uuid,display_name text,onboarding_complete boolean,bone_count bigint,
  total_meters bigint,total_bones bigint,total_piles bigint,active_marker_id text,
  home_lat double precision,home_lon double precision,home_changed_at timestamptz,
  walking_mode_enabled boolean,bark_enabled boolean,vibration_enabled boolean,
  is_admin boolean,is_suspended boolean,requires_new_name boolean,created_at timestamptz,
  level integer,xp_total numeric,xp_current_level numeric,xp_next_level numeric,
  xp_from_bones numeric,xp_from_walking numeric,xp_from_piles numeric,
  pending_level_from integer,pending_level_to integer,pending_level_bones bigint,pending_level_notice boolean
) language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  return query select p.id,p.display_name,p.onboarding_complete,p.bone_count,p.total_meters,p.total_bones,p.total_piles,p.active_marker_id,
    p.home_lat,p.home_lon,p.home_changed_at,p.walking_mode_enabled,p.bark_enabled,p.vibration_enabled,private.is_admin(uid),
    (coalesce(p.suspended_permanently,false) or coalesce(p.suspended_until>now(),false)),p.requires_new_name,p.created_at,
    p.player_level,p.xp_total,p.xp_total-c.cumulative_xp,coalesce(n.cumulative_xp-c.cumulative_xp,0),
    p.xp_from_bones,p.xp_from_walking,p.xp_from_piles,p.pending_level_from,p.pending_level_to,p.pending_level_bones,p.pending_level_notice
  from public.profiles p join public.level_curve c on c.level=p.player_level left join public.level_curve n on n.level=p.player_level+1
  where p.id=uid and p.deleted_at is null;
end $$;

create or replace function public.dismiss_level_notice()
returns void language sql security definer set search_path='' as $$
  update public.profiles set pending_level_from=null,pending_level_to=null,pending_level_bones=0,pending_level_notice=false,updated_at=now() where id=auth.uid()
$$;

create or replace function public.set_admin_mode(p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  if p_enabled then perform private.assert_admin(uid);end if;
  update public.player_presence pp set admin_mode=p_enabled,updated_at=now() where pp.player_id=uid;
end $$;

create or replace function public.add_distance_batch(client_batch_id uuid,meters integer,sample_started_at timestamptz,sample_ended_at timestamptz)
returns bigint language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();result bigint;elapsed_seconds double precision;maximum_plausible_meters integer;accepted boolean;
  combined_reward integer;bone_reward integer;new_balance bigint;xp_units integer;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if; perform private.assert_active_player(uid);
  elapsed_seconds:=extract(epoch from(sample_ended_at-sample_started_at));maximum_plausible_meters:=ceil(greatest(elapsed_seconds,0)*3.34+35)::integer;
  if meters<0 or meters>200000 or sample_ended_at<sample_started_at or sample_ended_at-sample_started_at>interval '2 hours'
    or sample_ended_at>now()+interval '5 minutes' or sample_started_at<now()-interval '3 hours' or meters>maximum_plausible_meters then raise exception 'INVALID_DISTANCE_BATCH' using errcode='22023'; end if;
  insert into public.distance_batches(player_id,client_batch_id,meters,sample_started_at,sample_ended_at)
  values(uid,client_batch_id,meters,sample_started_at,sample_ended_at) on conflict on constraint distance_batches_player_id_client_batch_id_key do nothing;accepted:=found;
  if accepted then
    select p.walking_reward_remainder+meters,p.xp_walk_remainder_m+meters into combined_reward,xp_units from public.profiles p where p.id=uid for update;
    bone_reward:=combined_reward/3000;
    update public.profiles p set total_meters=p.total_meters+meters,walking_reward_remainder=combined_reward%3000,
      xp_walk_remainder_m=xp_units%500,bone_count=p.bone_count+bone_reward,updated_at=now() where p.id=uid returning p.total_meters,p.bone_count into result,new_balance;
    if bone_reward>0 then insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id) values(uid,bone_reward,new_balance,'walking_reward',client_batch_id);end if;
    perform private.award_xp(uid,(xp_units/500)::numeric,'walking',client_batch_id);
  else select p.total_meters into result from public.profiles p where p.id=uid; end if; return result;
end $$;

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
    update public.world_bones w set active=false,collected_at=now(),respawn_at=now()+interval '5 minutes',updated_at=now() where w.id=wb.id;
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

create or replace function public.open_dirt_pile(p_pile_id uuid)
returns table(claim_id uuid,bone_type smallint,quantity smallint,cost integer,reward_value integer,balance bigint,is_double boolean)
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();me public.player_presence%rowtype;pile public.dirt_piles%rowtype;tier public.pile_types%rowtype;selected_type smallint;unit_value integer;qty smallint:=1;new_balance bigint;cid uuid;recipient record;pile_xp integer;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;perform private.assert_active_player(uid);
  select pp.* into me from public.player_presence pp where pp.player_id=uid;if not found or me.updated_at<now()-interval '90 seconds' or me.accuracy_m>75 then raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';end if;
  select dp.* into pile from public.dirt_piles dp where dp.id=p_pile_id for update;if not found or not pile.active then raise exception 'PILE_ALREADY_CLAIMED' using errcode='P0001';end if;
  if private.distance_meters(me.latitude,me.longitude,pile.latitude,pile.longitude)>greatest(25,least(me.accuracy_m,60)) then raise exception 'PILE_OUT_OF_RANGE' using errcode='P0001';end if;
  select pt.* into tier from public.pile_types pt where pt.id=pile.pile_type;if not found or pile.cost<>tier.cost then raise exception 'INVALID_PILE_CONFIGURATION' using errcode='P0001';end if;
  select p.bone_count into new_balance from public.profiles p where p.id=uid for update;if new_balance<tier.cost then raise exception 'INSUFFICIENT_BONES' using errcode='P0001';end if;
  if private.random_per_million()<tier.double_chance_per_million then qty:=2;selected_type:=private.pick_double_pile_bone(tier.cost);else selected_type:=private.pick_normal_pile_bone(tier.cost);end if;
  select bt.value into unit_value from public.bone_types bt where bt.id=selected_type;if unit_value<tier.cost then raise exception 'PILE_REWARD_BELOW_COST';end if;
  update public.profiles p set bone_count=p.bone_count-tier.cost,updated_at=now() where p.id=uid;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id) select uid,-tier.cost,p.bone_count,'dirt_pile_cost',pile.id from public.profiles p where p.id=uid;
  update public.profiles p set bone_count=p.bone_count+(unit_value*qty),total_bones=p.total_bones+qty,total_piles=p.total_piles+1,updated_at=now() where p.id=uid returning p.bone_count into new_balance;
  insert into public.player_bone_collection(player_id,bone_type,lifetime_count,first_discovered_at,updated_at) values(uid,selected_type,qty,now(),now()) on conflict on constraint player_bone_collection_pkey do update set lifetime_count=public.player_bone_collection.lifetime_count+excluded.lifetime_count,first_discovered_at=coalesce(public.player_bone_collection.first_discovered_at,now()),updated_at=now();
  insert into public.pile_claims(pile_id,pile_generation,player_id,cost,bone_type,quantity,reward_value) values(pile.id,pile.generation,uid,tier.cost,selected_type,qty,unit_value*qty) returning id into cid;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id) values(uid,unit_value*qty,new_balance,'dirt_pile_reward',cid);
  pile_xp:=case tier.cost when 10 then 5 when 25 then 10 when 50 then 20 when 100 then 40 else 100 end;
  for recipient in select pp.player_id from public.player_presence pp join public.profiles p on p.id=pp.player_id where pp.updated_at>=now()-interval '45 seconds' and pp.accuracy_m<=75 and not pp.admin_mode and p.deleted_at is null and private.distance_meters(pp.latitude,pp.longitude,pile.latitude,pile.longitude)<=greatest(25,least(pp.accuracy_m,60)) loop
    perform private.award_xp(recipient.player_id,pile_xp,'dirt_pile',cid);
  end loop;
  update public.dirt_piles dp set active=false,claimed_at=now(),respawn_at=now()+(interval '5 minutes'+random()*interval '5 minutes'),updated_at=now() where dp.id=pile.id;
  claim_id:=cid;bone_type:=selected_type;quantity:=qty;cost:=tier.cost;reward_value:=unit_value*qty;balance:=new_balance;is_double:=qty=2;return next;
end $$;

create or replace function public.get_latest_shared_bone_reward()
returns table(collection_id uuid,bone_type smallint,bone_value integer,created_at timestamptz)
language sql stable security definer set search_path='' as $$
  select c.id,c.bone_type,c.bone_value,c.collected_at
  from public.bone_collection_rewards r
  join public.bone_collections c on c.id=r.collection_id
  where r.player_id=auth.uid() and c.initiator_id<>auth.uid()
  order by c.collected_at desc,c.id desc limit 1
$$;

create or replace function public.buy_shop_item(p_poi_id uuid,p_item_id text,p_client_request_id uuid)
returns table(purchase_id uuid,item_id text,price bigint,balance bigint,already_owned boolean)
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();me public.player_presence%rowtype;poi public.game_pois%rowtype;shop_item public.shop_items%rowtype;prior public.shop_purchases%rowtype;new_balance bigint;pid uuid;entitled boolean;charged_price bigint;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;perform private.assert_active_player(uid);
  select s.* into prior from public.shop_purchases s where s.player_id=uid and s.client_request_id=p_client_request_id;
  if found then purchase_id:=prior.id;item_id:=prior.item_id;price:=prior.price;select p.bone_count into balance from public.profiles p where p.id=uid;already_owned:=true;return next;return;end if;
  select i.* into shop_item from public.shop_items i where i.id=p_item_id and i.active;if not found then raise exception 'SHOP_ITEM_NOT_FOUND' using errcode='P0001';end if;
  if exists(select 1 from public.player_items pi where pi.player_id=uid and pi.item_id=p_item_id) then raise exception 'ITEM_ALREADY_OWNED' using errcode='P0001';end if;
  select pp.* into me from public.player_presence pp where pp.player_id=uid;
  if not found or me.updated_at<now()-interval '90 seconds' or me.accuracy_m>75 then raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';end if;
  select gp.* into poi from public.game_pois gp where gp.id=p_poi_id and gp.active and gp.has_game_shop;if not found then raise exception 'GAME_SHOP_NOT_FOUND' using errcode='P0001';end if;
  if private.distance_meters(me.latitude,me.longitude,poi.latitude,poi.longitude)>50+least(me.accuracy_m,50) then raise exception 'SHOP_OUT_OF_RANGE' using errcode='P0001';end if;
  select exists(select 1 from public.player_entitlements e where e.player_id=uid and e.item_id=p_item_id) into entitled;
  select p.bone_count into new_balance from public.profiles p where p.id=uid for update;charged_price:=case when entitled then 0 else shop_item.price end;
  if new_balance<charged_price then raise exception 'INSUFFICIENT_BONES' using errcode='P0001';end if;
  if charged_price>0 then update public.profiles p set bone_count=p.bone_count-charged_price,updated_at=now() where p.id=uid returning p.bone_count into new_balance;end if;
  insert into public.shop_purchases(player_id,item_id,poi_id,client_request_id,price) values(uid,p_item_id,p_poi_id,p_client_request_id,charged_price) returning id into pid;
  insert into public.player_items(player_id,item_id,acquisition_source) values(uid,p_item_id,case when entitled then 'entitlement' else 'shop' end);
  if charged_price>0 then insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id) values(uid,-charged_price,new_balance,'shop_purchase',pid);end if;
  purchase_id:=pid;item_id:=p_item_id;price:=charged_price;balance:=new_balance;already_owned:=false;return next;
exception when unique_violation then raise exception 'ITEM_ALREADY_OWNED' using errcode='P0001';
end $$;

create or replace function public.admin_adjust_xp(p_player_id uuid,p_mode text,p_amount numeric,p_reason text)
returns table(xp_total numeric,level integer) language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();reason text;old numeric;new numeric;new_level integer;
begin
  perform private.assert_admin(uid);reason:=private.require_admin_reason(p_reason);
  if p_mode not in('add','subtract','set') or p_amount<0 or p_amount>100000000 then raise exception 'INVALID_XP_ADJUSTMENT' using errcode='22023';end if;
  select p.xp_total into old from public.profiles p where p.id=p_player_id for update;if not found then raise exception 'PLAYER_NOT_FOUND';end if;
  new:=case p_mode when 'add' then old+p_amount when 'subtract' then greatest(0,old-p_amount) else p_amount end;new_level:=private.level_for_xp(new);
  update public.profiles p set xp_total=new,player_level=new_level,highest_level=greatest(p.highest_level,new_level),updated_at=now() where p.id=p_player_id;
  insert into public.player_xp_ledger(player_id,amount,source,total_after,level_after,is_admin_adjustment) values(p_player_id,new-old,'admin_adjustment',new,new_level,true);
  insert into public.admin_audit_log(admin_id,action,target_player_id,reason,details) values(uid,'adjust_xp',p_player_id,reason,jsonb_build_object('mode',p_mode,'amount',p_amount,'before',old,'after',new));
  xp_total:=new;level:=new_level;return next;
end $$;

drop function if exists public.admin_search_players(text);
create function public.admin_search_players(p_search text default null)
returns table(player_id uuid,display_name text,bone_count bigint,is_suspended boolean,requires_new_name boolean,created_at timestamptz,level integer,xp_total numeric)
language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=auth.uid();needle text:=lower(trim(coalesce(p_search,'')));
begin
  perform private.assert_admin(uid);
  return query select p.id,p.display_name,p.bone_count,coalesce(p.suspended_permanently,false) or coalesce(p.suspended_until>now(),false),coalesce(p.requires_new_name,false),p.created_at,p.player_level,p.xp_total
  from public.profiles p where p.deleted_at is null and(needle='' or lower(p.display_name) like '%'||needle||'%' or p.id::text=needle)
  order by lower(p.display_name),p.id limit 100;
end $$;

revoke execute on function public.dismiss_level_notice() from public,anon;
drop function if exists public.get_flock_members(uuid);
create function public.get_flock_members(p_flock_id uuid)
returns table(player_id uuid,display_name text,role text,joined_at timestamptz,bone_balance bigint,total_meters bigint,total_bones bigint,total_piles bigint,collection jsonb,level integer,xp_total numeric)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  if not private.is_flock_member(p_flock_id,auth.uid()) then raise exception 'FLOCK_MEMBER_REQUIRED' using errcode='42501';end if;
  return query select p.id,p.display_name,fm.role,fm.joined_at,p.bone_count,p.total_meters,p.total_bones,p.total_piles,
    coalesce((select jsonb_agg(jsonb_build_object('bone_type',c.bone_type,'count',c.lifetime_count) order by c.bone_type) from public.player_bone_collection c where c.player_id=p.id),'[]'::jsonb),p.player_level,p.xp_total
  from public.flock_members fm join public.profiles p on p.id=fm.player_id where fm.flock_id=p_flock_id and p.deleted_at is null
  order by case fm.role when 'leader' then 0 when 'guard' then 1 else 2 end,lower(p.display_name),p.id;
end $$;

revoke execute on function public.set_admin_mode(boolean) from public,anon;
revoke execute on function public.admin_adjust_xp(uuid,text,numeric,text) from public,anon;
grant execute on function public.dismiss_level_notice() to authenticated;
grant execute on function public.set_admin_mode(boolean) to authenticated;
grant execute on function public.admin_adjust_xp(uuid,text,numeric,text) to authenticated;
grant execute on function public.admin_search_players(text) to authenticated;
grant execute on function public.get_flock_members(uuid) to authenticated;
grant execute on function public.get_session_bootstrap() to authenticated;
grant execute on function public.add_distance_batch(uuid,integer,timestamptz,timestamptz) to authenticated;
grant execute on function public.collect_nearby_bones() to authenticated;
grant execute on function public.open_dirt_pile(uuid) to authenticated;
grant execute on function public.get_latest_shared_bone_reward() to authenticated;
grant execute on function public.buy_shop_item(uuid,text,uuid) to authenticated;

do $$ begin
  begin alter publication supabase_realtime add table public.player_xp_ledger;exception when duplicate_object then null;end;
end $$;
