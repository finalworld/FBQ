-- FBQ 0.500: hundsystem, privat aktivitetslogg och världstäckning.
create extension if not exists pgcrypto;

alter table public.profiles add column if not exists active_dog_id uuid;
alter table public.profiles add column if not exists dog_card_collapsed boolean not null default false;

create table if not exists public.player_event_log(
  id bigint generated always as identity primary key,
  player_id uuid not null references auth.users(id) on delete cascade,
  category text not null check(category in('bone','xp','purchase','pile','walking','other')),
  title text not null,
  bone_delta bigint not null default 0,
  xp_delta numeric not null default 0,
  details jsonb not null default '{}'::jsonb,
  source_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists player_event_log_owner_time on public.player_event_log(player_id,created_at desc);
alter table public.player_event_log enable row level security;
drop policy if exists player_event_log_owner_read on public.player_event_log;
create policy player_event_log_owner_read on public.player_event_log for select to authenticated using(player_id=auth.uid());
revoke insert,update,delete on public.player_event_log from anon,authenticated;

create table if not exists public.dogs(
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  breed smallint not null check(breed between 0 and 9),
  gender text not null check(gender in('female','male')),
  development_km smallint not null check(development_km in(20,25,30)),
  stage smallint not null default 0 check(stage between 0 and 5),
  distance_meters bigint not null default 0 check(distance_meters>=0),
  perk_candidates smallint[] not null,
  perk_primary smallint,
  perk_primary_level smallint check(perk_primary_level between 1 and 5),
  perk_secondary smallint,
  perk_secondary_level smallint check(perk_secondary_level between 1 and 5),
  is_active boolean not null default false,
  is_puppy boolean not null default true,
  found_pile_type smallint not null check(found_pile_type between 0 and 4),
  found_area text,
  found_at timestamptz not null default now(),
  renamed_at timestamptz,
  updated_at timestamptz not null default now()
);
create unique index if not exists one_player_puppy on public.dogs(player_id) where is_puppy;
create unique index if not exists one_active_dog on public.dogs(player_id) where is_active;
alter table public.profiles drop constraint if exists profiles_active_dog_id_fkey;
alter table public.profiles add constraint profiles_active_dog_id_fkey foreign key(active_dog_id) references public.dogs(id) on delete set null;
alter table public.dogs enable row level security;
drop policy if exists dogs_owner_read on public.dogs;
create policy dogs_owner_read on public.dogs for select to authenticated using(player_id=auth.uid());
revoke insert,update,delete on public.dogs from anon,authenticated;

create table if not exists public.pending_puppies(
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  pile_claim_id uuid not null unique references public.pile_claims(id) on delete cascade,
  breed smallint not null check(breed between 0 and 9),
  gender text not null check(gender in('female','male')),
  development_km smallint not null check(development_km in(20,25,30)),
  perk_candidates smallint[] not null,
  perk_primary smallint not null check(perk_primary between 0 and 9),
  perk_primary_level smallint not null check(perk_primary_level between 1 and 5),
  perk_secondary smallint check(perk_secondary between 0 and 9),
  perk_secondary_level smallint check(perk_secondary_level between 1 and 5),
  found_pile_type smallint not null,
  found_area text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolution text check(resolution in('kept_new','kept_old','kennel'))
);
alter table public.pending_puppies enable row level security;
drop policy if exists pending_puppies_owner_read on public.pending_puppies;
create policy pending_puppies_owner_read on public.pending_puppies for select to authenticated using(player_id=auth.uid());
revoke insert,update,delete on public.pending_puppies from anon,authenticated;

create or replace function private.dog_perk_level(p_tier integer) returns smallint language plpgsql volatile set search_path='' as $$
declare r integer:=floor(random()*100)::integer;
begin return case p_tier
 when 0 then case when r<55 then 1 when r<80 then 2 when r<92 then 3 when r<98 then 4 else 5 end
 when 1 then case when r<40 then 1 when r<70 then 2 when r<87 then 3 when r<96 then 4 else 5 end
 when 2 then case when r<25 then 1 when r<55 then 2 when r<80 then 3 when r<94 then 4 else 5 end
 when 3 then case when r<15 then 1 when r<40 then 2 when r<70 then 3 when r<90 then 4 else 5 end
 else case when r<10 then 1 when r<30 then 2 when r<55 then 3 when r<80 then 4 else 5 end end;
end $$;

create or replace function private.create_puppy_after_pile() returns trigger language plpgsql security definer set search_path='' as $$
declare p public.dirt_piles%rowtype;r integer;dev smallint;primary_perk smallint;secondary_perk smallint;candidate_list smallint[]:=array[0,1,2,3,4,5,6,7,8,9];
begin
  if random()>=0.50 then return new;end if;
  if exists(select 1 from public.pending_puppies x where x.player_id=new.player_id and x.resolved_at is null) then return new;end if;
  select d.* into p from public.dirt_piles d where d.id=new.pile_id;r:=floor(random()*100)::integer;
  dev:=case p.pile_type when 0 then case when r<50 then 20 when r<80 then 25 else 30 end when 1 then case when r<45 then 20 when r<75 then 25 else 30 end when 2 then case when r<40 then 20 when r<70 then 25 else 30 end when 3 then case when r<35 then 20 when r<65 then 25 else 30 end else case when r<30 then 20 when r<60 then 25 else 30 end end;
  primary_perk:=floor(random()*10)::smallint;
  if random()<0.05 then loop secondary_perk:=floor(random()*10)::smallint;exit when secondary_perk<>primary_perk;end loop;end if;
  insert into public.pending_puppies(player_id,pile_claim_id,breed,gender,development_km,perk_candidates,perk_primary,perk_primary_level,perk_secondary,perk_secondary_level,found_pile_type,found_area)
  values(new.player_id,new.id,floor(random()*10)::smallint,case when random()<0.5 then 'female' else 'male' end,dev,candidate_list,primary_perk,private.dog_perk_level(p.pile_type),secondary_perk,case when secondary_perk is null then null else private.dog_perk_level(p.pile_type) end,p.pile_type,'Området kring fyndplatsen');
  return new;
end $$;
drop trigger if exists create_puppy_after_pile on public.pile_claims;
create trigger create_puppy_after_pile after insert on public.pile_claims for each row execute function private.create_puppy_after_pile();

create or replace function public.get_pending_puppy() returns table(id uuid,breed smallint,gender text,development_km smallint,found_pile_type smallint,found_area text,created_at timestamptz)
language sql stable security definer set search_path='' as $$ select p.id,p.breed,p.gender,p.development_km,p.found_pile_type,p.found_area,p.created_at from public.pending_puppies p where p.player_id=auth.uid() and p.resolved_at is null order by p.created_at desc limit 1 $$;

create or replace function public.resolve_pending_puppy(p_pending_id uuid,p_keep_new boolean,p_name text default 'Valpen',p_replace_dog_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();p public.pending_puppies%rowtype;dog_id uuid;adult_count integer;
begin
  select x.* into p from public.pending_puppies x where x.id=p_pending_id and x.player_id=uid and x.resolved_at is null for update;if not found then raise exception 'PUPPY_NOT_FOUND';end if;
  if not p_keep_new then update public.pending_puppies set resolved_at=now(),resolution='kept_old' where id=p.id;return null;end if;
  if exists(select 1 from public.dogs d where d.player_id=uid and d.is_puppy) then delete from public.dogs d where d.player_id=uid and d.is_puppy;end if;
  select count(*) into adult_count from public.dogs d where d.player_id=uid and not d.is_puppy;
  if adult_count>=19 then if p_replace_dog_id is null then raise exception 'DOG_CAPACITY_REACHED';end if;delete from public.dogs d where d.id=p_replace_dog_id and d.player_id=uid and not d.is_puppy;if not found then raise exception 'REPLACEMENT_DOG_NOT_FOUND';end if;end if;
  update public.dogs set is_active=false where player_id=uid;
  insert into public.dogs(player_id,name,breed,gender,development_km,perk_candidates,perk_primary,perk_primary_level,perk_secondary,perk_secondary_level,is_active,is_puppy,found_pile_type,found_area)
  values(uid,left(coalesce(nullif(trim(p_name),''),'Valpen'),20),p.breed,p.gender,p.development_km,p.perk_candidates,p.perk_primary,p.perk_primary_level,p.perk_secondary,p.perk_secondary_level,true,true,p.found_pile_type,p.found_area) returning id into dog_id;
  update public.profiles set active_dog_id=dog_id where id=uid;update public.pending_puppies set resolved_at=now(),resolution='kept_new' where id=p.id;return dog_id;
end $$;

create or replace function public.get_my_dogs() returns table(id uuid,name text,breed smallint,gender text,development_km smallint,stage smallint,distance_meters bigint,visible_perks smallint[],perk_primary smallint,perk_primary_level smallint,perk_secondary smallint,perk_secondary_level smallint,is_active boolean,is_puppy boolean,found_area text,found_at timestamptz,renamed_at timestamptz)
language sql stable security definer set search_path='' as $$
 select d.id,d.name,d.breed,d.gender,d.development_km,d.stage,d.distance_meters,
 case when d.stage>=5 then array[d.perk_primary]::smallint[] else d.perk_candidates[1:greatest(2,10-d.stage*2)] end,
 case when d.stage>=5 then d.perk_primary else null end,case when d.stage>=5 then d.perk_primary_level else null end,case when d.stage>=5 then d.perk_secondary else null end,case when d.stage>=5 then d.perk_secondary_level else null end,d.is_active,d.is_puppy,d.found_area,d.found_at,d.renamed_at
 from public.dogs d where d.player_id=auth.uid() order by d.is_active desc,d.found_at desc;
$$;

create or replace function public.set_active_dog(p_dog_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();me public.player_presence%rowtype;p public.profiles%rowtype;
begin select * into p from public.profiles where id=uid;select * into me from public.player_presence where player_id=uid;if p.home_lat is null or me.updated_at<now()-interval '90 seconds' or private.distance_meters(me.latitude,me.longitude,p.home_lat,p.home_lon)>50+least(me.accuracy_m,50) then raise exception 'HOME_REQUIRED';end if;if exists(select 1 from public.dogs where player_id=uid and is_puppy and id<>p_dog_id) then raise exception 'PUPPY_MUST_STAY_ACTIVE';end if;update public.dogs set is_active=(id=p_dog_id) where player_id=uid;if not found or not exists(select 1 from public.dogs where id=p_dog_id and player_id=uid) then raise exception 'DOG_NOT_FOUND';end if;update public.profiles set active_dog_id=p_dog_id where id=uid;end $$;

create or replace function public.rename_active_dog(p_name text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();d public.dogs%rowtype;begin if trim(p_name)!~'^[[:alnum:]ÅÄÖåäö ]{1,20}$' then raise exception 'INVALID_DOG_NAME';end if;select * into d from public.dogs where player_id=uid and is_active for update;if not found then raise exception 'NO_ACTIVE_DOG';end if;if d.renamed_at is not null and d.renamed_at>now()-interval '24 hours' then raise exception 'DOG_RENAME_COOLDOWN';end if;update public.profiles set bone_count=bone_count-100 where id=uid and bone_count>=100;if not found then raise exception 'INSUFFICIENT_BONES';end if;update public.dogs set name=trim(p_name),renamed_at=now(),updated_at=now() where id=d.id;end $$;

create or replace function public.send_dog_to_kennel(p_dog_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();d public.dogs%rowtype;p public.profiles%rowtype;me public.player_presence%rowtype;begin select * into d from public.dogs where id=p_dog_id and player_id=uid for update;if not found then raise exception 'DOG_NOT_FOUND';end if;select * into p from public.profiles where id=uid;select * into me from public.player_presence where player_id=uid;if me.updated_at is null or me.updated_at<now()-interval '90 seconds' or not(coalesce(private.distance_meters(me.latitude,me.longitude,p.home_lat,p.home_lon)<=50+least(me.accuracy_m,50),false) or exists(select 1 from public.dirt_piles x where x.active and private.distance_meters(me.latitude,me.longitude,x.latitude,x.longitude)<=30)) then raise exception 'HOME_OR_PILE_REQUIRED';end if;delete from public.dogs where id=d.id;if d.is_active then update public.profiles set active_dog_id=null where id=uid;end if;end $$;

create or replace function public.get_my_event_log(p_category text default null,p_limit integer default 100)
returns table(id bigint,category text,title text,bone_delta bigint,xp_delta numeric,details jsonb,created_at timestamptz)
language sql stable security definer set search_path='' as $$ select e.id,e.category,e.title,e.bone_delta,e.xp_delta,e.details,e.created_at from public.player_event_log e where e.player_id=auth.uid() and(p_category is null or e.category=p_category) order by e.created_at desc limit least(greatest(p_limit,1),100) $$;

create or replace function private.log_bone_ledger_event() returns trigger language plpgsql security definer set search_path='' as $$ begin insert into public.player_event_log(player_id,category,title,bone_delta,details,source_id) values(new.player_id,case when new.reason like '%pile%' then 'pile' when new.reason like '%shop%' then 'purchase' else 'bone' end,case new.reason when 'dirt_pile_cost' then 'Jordhög – insats' when 'dirt_pile_reward' then 'Jordhög – vinst' when 'shop_purchase' then 'Köp' when 'home_slot_stake' then 'Hemmaautomaten – insats' when 'home_slot_payout' then 'Hemmaautomaten – vinst' else 'Ben' end,new.amount,jsonb_build_object('reason',new.reason,'balance_after',new.balance_after),new.source_id);return new;end $$;
drop trigger if exists log_bone_ledger_event on public.player_bone_ledger;create trigger log_bone_ledger_event after insert on public.player_bone_ledger for each row execute function private.log_bone_ledger_event();
create or replace function private.log_xp_ledger_event() returns trigger language plpgsql security definer set search_path='' as $$ begin insert into public.player_event_log(player_id,category,title,xp_delta,details,source_id) values(new.player_id,case when new.source like '%walk%' then 'walking' else 'xp' end,case when new.source like '%walk%' then 'Promenad' else 'XP' end,new.amount,jsonb_build_object('source',new.source,'total_after',new.total_after,'level_after',new.level_after),new.source_id);return new;end $$;
drop trigger if exists log_xp_ledger_event on public.player_xp_ledger;create trigger log_xp_ledger_event after insert on public.player_xp_ledger for each row execute function private.log_xp_ledger_event();

-- Låt aktiva hundar växa av godkänd gångsträcka. Fem lika delar, vuxen vid steg 5.
create or replace function private.progress_active_dog() returns trigger language plpgsql security definer set search_path='' as $$
declare d public.dogs%rowtype;new_stage smallint;reward integer;begin select * into d from public.dogs where player_id=new.player_id and is_active for update;if not found then return new;end if;update public.dogs set distance_meters=distance_meters+new.meters,updated_at=now() where id=d.id returning * into d;new_stage:=least(5,floor((d.distance_meters::numeric/(d.development_km*1000))*5)::integer);if new_stage>d.stage then reward:=case d.development_km when 20 then (array[2,5,8,12,23])[new_stage] when 25 then (array[3,7,12,18,35])[new_stage] else (array[4,10,16,25,45])[new_stage] end;update public.dogs set stage=new_stage,is_puppy=(new_stage<5),updated_at=now() where id=d.id;update public.profiles set bone_count=bone_count+reward where id=new.player_id;insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id) select new.player_id,reward,p.bone_count,'dog_growth_reward',d.id from public.profiles p where p.id=new.player_id;end if;return new;end $$;
drop trigger if exists progress_active_dog on public.distance_batches;create trigger progress_active_dog after insert on public.distance_batches for each row execute function private.progress_active_dog();

-- Realtime även för manuellt placerade butiker och hunddata.
do $$ begin begin alter publication supabase_realtime add table public.game_pois;exception when duplicate_object then null;end;begin alter publication supabase_realtime add table public.dogs;exception when duplicate_object then null;end;begin alter publication supabase_realtime add table public.pending_puppies;exception when duplicate_object then null;end;end $$;
revoke execute on function public.resolve_pending_puppy(uuid,boolean,text,uuid) from public,anon;grant execute on function public.resolve_pending_puppy(uuid,boolean,text,uuid) to authenticated;
grant execute on function public.get_pending_puppy(),public.get_my_dogs(),public.set_active_dog(uuid),public.rename_active_dog(text),public.send_dog_to_kennel(uuid),public.get_my_event_log(text,integer) to authenticated;
