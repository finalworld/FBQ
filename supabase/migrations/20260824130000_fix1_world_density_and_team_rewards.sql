-- Fix 1.2: denser local world, fewer one-point bones, and durable team rewards.

-- 1-value bones drop from roughly 42% to 25%; useful mid/high tiers become commoner.
update public.bone_types b set spawn_weight=v.spawn_weight
from (values
  (0::smallint,2500),(1::smallint,2100),(2::smallint,1700),(3::smallint,1200),
  (4::smallint,850),(5::smallint,600),(6::smallint,400),(7::smallint,280),
  (8::smallint,170),(9::smallint,110),(10::smallint,65),(11::smallint,25)
) v(id,spawn_weight) where b.id=v.id;

-- Keep the proven maintenance code, but tune its latest installed definition.
-- Bones: 140 within 2 km, minimum 100 m apart. Piles: 24 within 2 km,
-- minimum 250 m apart. Maintenance is called separately from GPS/actions.
do $$ declare d text; begin
  d:=pg_get_functiondef('private.ensure_close_bones(double precision,double precision)'::regprocedure);
  d:=replace(d,'< 200','< 100'); d:=replace(d,'<200','<100'); execute d;
  d:=pg_get_functiondef('private.maintain_world_bones(double precision,double precision)'::regprocedure);
  d:=replace(d,'< 200','< 100'); d:=replace(d,'<200','<100');
  d:=replace(d,'<= 3000','<= 2000'); d:=replace(d,'<=3000','<=2000');
  d:=replace(d,'< 100 AND created < 100','< 140 AND created < 40');
  d:=replace(d,'<100 and created<100','<140 and created<40'); execute d;
  d:=pg_get_functiondef('private.maintain_dirt_piles(double precision,double precision)'::regprocedure);
  d:=replace(d,'< 350','< 250'); d:=replace(d,'<350','<250');
  d:=replace(d,'<= 2800','<= 1900'); d:=replace(d,'<=2800','<=1900');
  d:=replace(d,'<= 3000','<= 2000'); d:=replace(d,'<=3000','<=2000');
  d:=replace(d,'n < 16','n < 24'); d:=replace(d,'n<16','n<24');
  d:=replace(d,'n + 1..16','n + 1..24'); d:=replace(d,'n+1..16','n+1..24'); execute d;
end $$;

create or replace function public.refresh_world_nearby(p_latitude double precision,p_longitude double precision)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); begin
  if uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then raise exception 'GPS_REQUIRED'; end if;
  perform set_config('statement_timeout','12s',true);
  perform private.maintain_world_bones(p_latitude,p_longitude);
  perform private.maintain_dirt_piles(p_latitude,p_longitude);
  return jsonb_build_object('ok',true,'radius_m',2000,'bone_spacing_m',100,'pile_spacing_m',250);
end $$;
revoke execute on function public.refresh_world_nearby(double precision,double precision) from public,anon;
grant execute on function public.refresh_world_nearby(double precision,double precision) to authenticated;

-- Treasure frames are actual marker items, so they appear under Equipment.
insert into public.shop_items(id,name_sv,main_category,subcategory,rarity,price,asset_name,sort_order,active,is_default)
select f.id,f.name_sv,'Markörer','Skattjaktsmarkörer','rare',0,f.id,900+row_number() over(order by f.id),true,false
from public.treasure_frames f
on conflict(id) do update set name_sv=excluded.name_sv,main_category=excluded.main_category,
  subcategory=excluded.subcategory,rarity=excluded.rarity,price=0,asset_name=excluded.asset_name,active=true;

insert into public.player_items(player_id,item_id,acquisition_source)
select player_id,frame_id,'treasure_hunt' from public.player_treasure_frames on conflict do nothing;

create table if not exists public.treasure_hunt_rewards(
  hunt_id uuid not null references public.treasure_hunts(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  xp_reward integer not null,
  frame_id text not null references public.treasure_frames(id),
  frame_name text not null,
  created_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  primary key(hunt_id,player_id)
);
alter table public.treasure_hunt_rewards enable row level security;
drop policy if exists treasure_rewards_owner_read on public.treasure_hunt_rewards;
create policy treasure_rewards_owner_read on public.treasure_hunt_rewards for select to authenticated using(player_id=auth.uid());
revoke insert,update,delete on public.treasure_hunt_rewards from anon,authenticated;
grant select on public.treasure_hunt_rewards to authenticated;

create or replace function public.get_pending_treasure_reward()
returns table(hunt_id uuid,claimed boolean,sequence integer,completed boolean,xp_reward integer,frame_id text,frame_name text)
language sql stable security definer set search_path='' as $$
  select r.hunt_id,true,0,true,r.xp_reward,r.frame_id,r.frame_name
  from public.treasure_hunt_rewards r where r.player_id=auth.uid() and r.acknowledged_at is null
  order by r.created_at limit 1
$$;

create or replace function public.acknowledge_treasure_reward(p_hunt_id uuid)
returns void language sql security definer set search_path='' as $$
  update public.treasure_hunt_rewards set acknowledged_at=now()
  where hunt_id=p_hunt_id and player_id=auth.uid() and acknowledged_at is null
$$;
revoke execute on function public.get_pending_treasure_reward(),public.acknowledge_treasure_reward(uuid) from public,anon;
grant execute on function public.get_pending_treasure_reward(),public.acknowledge_treasure_reward(uuid) to authenticated;

drop function if exists public.claim_treasure_checkpoint(uuid);
create or replace function public.claim_treasure_checkpoint(p_checkpoint_id uuid,p_latitude double precision,p_longitude double precision,p_accuracy_m real)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();c public.treasure_checkpoints%rowtype;h public.treasure_hunts%rowtype;r record;
  done integer;total integer;reward_frame text;reward_name text;mine jsonb:=null;
begin
  if uid is null then raise exception 'AUTH_REQUIRED';end if;
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then raise exception 'GPS_REQUIRED';end if;
  if p_accuracy_m<0 or p_accuracy_m>75 then raise exception 'GPS_INACCURATE';end if;
  insert into public.player_presence(player_id,latitude,longitude,accuracy_m,is_background,updated_at)
    values(uid,p_latitude,p_longitude,p_accuracy_m,false,clock_timestamp()) on conflict(player_id) do update
    set latitude=excluded.latitude,longitude=excluded.longitude,accuracy_m=excluded.accuracy_m,is_background=false,updated_at=excluded.updated_at;
  select * into c from public.treasure_checkpoints where id=p_checkpoint_id;
  if not found then raise exception 'CHECKPOINT_GONE';end if;
  select * into h from public.treasure_hunts where id=c.hunt_id and status='active' for update;
  if not found then raise exception 'HUNT_NOT_ACTIVE';end if;
  if not exists(select 1 from public.treasure_hunt_participants where hunt_id=h.id and player_id=uid) then raise exception 'NOT_PARTICIPANT';end if;
  if private.distance_meters(p_latitude,p_longitude,c.latitude,c.longitude)>30+least(p_accuracy_m,25) then raise exception 'TOO_FAR';end if;
  for r in select hp.player_id from public.treasure_hunt_participants hp join public.player_presence pp on pp.player_id=hp.player_id
    where hp.hunt_id=h.id and hp.sharing_enabled and pp.updated_at>now()-interval '90 seconds' and pp.accuracy_m<=75
      and private.distance_meters(pp.latitude,pp.longitude,c.latitude,c.longitude)<=30+least(pp.accuracy_m,25)
  loop insert into public.treasure_checkpoint_progress(hunt_id,checkpoint_id,player_id) values(h.id,c.id,r.player_id) on conflict do nothing;end loop;
  select count(*) into total from public.treasure_checkpoints where hunt_id=h.id;
  for r in select player_id from public.treasure_hunt_participants where hunt_id=h.id loop
    select count(*) into done from public.treasure_checkpoint_progress where hunt_id=h.id and player_id=r.player_id;
    if done=total and not exists(select 1 from public.treasure_hunt_participants where hunt_id=h.id and player_id=r.player_id and completed_at is not null) then
      update public.treasure_hunt_participants set completed_at=now() where hunt_id=h.id and player_id=r.player_id;
      perform private.award_xp(r.player_id,h.xp_reward,'treasure_hunt',h.id);
      select f.id,f.name_sv into reward_frame,reward_name from public.treasure_frames f order by random() limit 1;
      insert into public.player_treasure_frames(player_id,frame_id,earned_at) values(r.player_id,reward_frame,now()) on conflict do nothing;
      insert into public.player_items(player_id,item_id,acquisition_source) values(r.player_id,reward_frame,'treasure_hunt') on conflict do nothing;
      insert into public.treasure_hunt_rewards(hunt_id,player_id,xp_reward,frame_id,frame_name)
        values(h.id,r.player_id,h.xp_reward,reward_frame,reward_name) on conflict do nothing;
      insert into public.player_event_log(player_id,category,title,xp_delta,details,source_id)
        values(r.player_id,'other','Skattjakt klar · +'||h.xp_reward||' XP · '||reward_name,0,
          jsonb_build_object('hunt_id',h.id,'xp_reward',h.xp_reward,'marker_id',reward_frame,'marker_name',reward_name),h.id);
      if r.player_id=uid then mine:=jsonb_build_object('hunt_id',h.id,'claimed',true,'sequence',c.sequence,'completed',true,'xp_reward',h.xp_reward,'frame_id',reward_frame,'frame_name',reward_name);end if;
    end if;
  end loop;
  if not exists(select 1 from public.treasure_hunt_participants where hunt_id=h.id and completed_at is null) then
    update public.treasure_hunts set status='completed',completed_at=now() where id=h.id;
  end if;
  return coalesce(mine,jsonb_build_object('hunt_id',h.id,'claimed',true,'sequence',c.sequence,'completed',false,'xp_reward',0,'frame_id',null,'frame_name',null));
end $$;
revoke execute on function public.claim_treasure_checkpoint(uuid,double precision,double precision,real) from public,anon;
grant execute on function public.claim_treasure_checkpoint(uuid,double precision,double precision,real) to authenticated;

notify pgrst,'reload schema';
