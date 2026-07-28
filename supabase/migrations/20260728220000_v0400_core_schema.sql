-- Frasse's Bone Quest 0.400
-- Core schema. Safe to run after the manually-created 0.300 prototype tables.
-- Economy mutations are deliberately added as SECURITY DEFINER RPCs in the
-- following migration; clients receive no direct write access to balances.

create extension if not exists pgcrypto;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Existing prototype tables -------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Frassevän',
  bone_count bigint not null default 0,
  total_meters bigint not null default 0,
  total_bones bigint not null default 0,
  total_piles bigint not null default 0,
  home_lat double precision,
  home_lon double precision,
  name_changed_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists onboarding_complete boolean not null default false,
  add column if not exists active_marker_id text not null default 'marker_default_paw',
  add column if not exists home_changed_at timestamptz,
  add column if not exists walking_mode_enabled boolean not null default false,
  add column if not exists bark_enabled boolean not null default true,
  add column if not exists vibration_enabled boolean not null default true,
  add column if not exists suspended_until timestamptz,
  add column if not exists suspended_permanently boolean not null default false,
  add column if not exists suspension_reason text,
  add column if not exists requires_new_name boolean not null default false,
  add column if not exists deleted_at timestamptz;

update public.profiles set display_name = 'Frassevän'
where display_name in ('FrassevÃ¤n', 'FrassevÃƒÂ¤n');

create table if not exists public.world_bones (
  id uuid primary key default gen_random_uuid(),
  latitude double precision not null,
  longitude double precision not null,
  bone_type integer not null check (bone_type between 0 and 11),
  active boolean not null default true,
  respawn_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.world_bones
  add column if not exists generation integer not null default 1,
  add column if not exists collected_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists placed_by uuid references auth.users(id) on delete set null,
  add column if not exists placement_source text not null default 'system';

create table if not exists public.dirt_piles (
  id uuid primary key default gen_random_uuid(),
  latitude double precision not null,
  longitude double precision not null,
  pile_type integer not null default 0,
  cost integer not null default 10,
  active boolean not null default true,
  respawn_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.dirt_piles
  add column if not exists generation integer not null default 1,
  add column if not exists claimed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists placed_by uuid references auth.users(id) on delete set null,
  add column if not exists placement_source text not null default 'system';

create table if not exists public.player_presence (
  player_id uuid primary key references auth.users(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  heading real not null default 0,
  moved_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.player_presence
  add column if not exists accuracy_m real not null default 9999,
  add column if not exists speed_mps real,
  add column if not exists is_background boolean not null default false;

-- Catalogues ----------------------------------------------------------------

create table if not exists public.bone_types (
  id smallint primary key check (id between 0 and 11),
  code text not null unique,
  name_sv text not null,
  value integer not null check (value > 0),
  spawn_weight integer not null check (spawn_weight > 0),
  sort_order smallint not null unique
);

insert into public.bone_types(id, code, name_sv, value, spawn_weight, sort_order) values
  (0, 'cracked', 'Sprucket ben', 1, 4200, 1),
  (1, 'worn', 'Slitet ben', 2, 2300, 2),
  (2, 'mossy', 'Mossigt ben', 3, 1400, 3),
  (3, 'polished', 'Polerat ben', 5, 850, 4),
  (4, 'clean', 'Rent ben', 8, 500, 5),
  (5, 'crystal', 'Kristallben', 12, 300, 6),
  (6, 'magic', 'Magiskt ben', 20, 180, 7),
  (7, 'golden', 'Gyllene ben', 35, 110, 8),
  (8, 'sapphire', 'Safirben', 60, 70, 9),
  (9, 'diamond', 'Diamantben', 100, 50, 10),
  (10, 'prismatic', 'Prismaben', 175, 30, 11),
  (11, 'frasse_king', 'Frasses kungaben', 300, 10, 12)
on conflict (id) do update set
  code = excluded.code, name_sv = excluded.name_sv, value = excluded.value,
  spawn_weight = excluded.spawn_weight, sort_order = excluded.sort_order;

create table if not exists public.pile_types (
  id smallint primary key check (id between 0 and 4),
  cost integer not null unique,
  double_chance_per_million integer not null,
  sort_order smallint not null unique
);
insert into public.pile_types(id, cost, double_chance_per_million, sort_order) values
  (0, 10, 1000, 1), (1, 25, 2000, 2), (2, 50, 4000, 3),
  (3, 100, 7000, 4), (4, 250, 10000, 5)
on conflict (id) do update set cost=excluded.cost,
  double_chance_per_million=excluded.double_chance_per_million,
  sort_order=excluded.sort_order;

create table if not exists public.shop_items (
  id text primary key,
  name_sv text not null,
  main_category text not null,
  subcategory text not null,
  rarity text not null check (rarity in ('free','common','uncommon','rare','epic','legendary','mythic')),
  price bigint not null check (price >= 0),
  asset_name text not null unique,
  sort_order integer not null,
  active boolean not null default true,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.shop_items
  (id,name_sv,main_category,subcategory,rarity,price,asset_name,sort_order,is_default)
values ('marker_default_paw','Standardtass','Markörer','Tassar','free',0,
        'marker_default_paw',1,true)
on conflict (id) do nothing;

-- Player-owned state ---------------------------------------------------------

create table if not exists public.player_bone_collection (
  player_id uuid not null references auth.users(id) on delete cascade,
  bone_type smallint not null references public.bone_types(id),
  lifetime_count bigint not null default 0 check (lifetime_count >= 0),
  first_discovered_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (player_id, bone_type)
);

create table if not exists public.player_items (
  player_id uuid not null references auth.users(id) on delete cascade,
  item_id text not null references public.shop_items(id),
  acquired_at timestamptz not null default now(),
  acquisition_source text not null,
  primary key(player_id, item_id)
);

create table if not exists public.player_settings (
  player_id uuid primary key references auth.users(id) on delete cascade,
  show_dog_parks boolean not null default true,
  show_pet_shops boolean not null default true,
  show_vets boolean not null default true,
  show_grooming boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.distance_batches (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  client_batch_id uuid not null,
  meters integer not null check (meters between 0 and 200000),
  sample_started_at timestamptz not null,
  sample_ended_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique(player_id, client_batch_id),
  check (sample_ended_at >= sample_started_at),
  check (sample_ended_at - sample_started_at <= interval '2 hours')
);

-- Immutable reward and economy records --------------------------------------

create table if not exists public.bone_collections (
  id uuid primary key default gen_random_uuid(),
  world_bone_id uuid not null references public.world_bones(id),
  world_generation integer not null,
  initiator_id uuid not null references auth.users(id),
  bone_type smallint not null references public.bone_types(id),
  bone_value integer not null check (bone_value > 0),
  collected_at timestamptz not null default now(),
  unique(world_bone_id, world_generation)
);

create table if not exists public.bone_collection_rewards (
  collection_id uuid not null references public.bone_collections(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  distance_m real not null,
  rewarded_at timestamptz not null default now(),
  primary key(collection_id, player_id)
);

create table if not exists public.pile_claims (
  id uuid primary key default gen_random_uuid(),
  pile_id uuid not null references public.dirt_piles(id),
  pile_generation integer not null,
  player_id uuid not null references auth.users(id) on delete cascade,
  cost integer not null check (cost > 0),
  bone_type smallint not null references public.bone_types(id),
  quantity smallint not null check (quantity in (1,2)),
  reward_value integer not null check (reward_value >= cost),
  claimed_at timestamptz not null default now(),
  unique(pile_id, pile_generation)
);

create table if not exists public.home_slot_spins (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  stake smallint not null check (stake in (1,2,5,10)),
  multiplier numeric(5,1) not null check (multiplier in (0,1,2,5,10,50)),
  payout integer not null check (payout >= 0),
  created_at timestamptz not null default now(),
  unique(player_id, client_request_id)
);

create table if not exists public.player_bone_ledger (
  id bigint generated always as identity primary key,
  player_id uuid not null references auth.users(id) on delete cascade,
  amount bigint not null check (amount <> 0),
  balance_after bigint not null check (balance_after >= 0),
  reason text not null,
  source_id uuid,
  created_at timestamptz not null default now()
);

-- Flocks --------------------------------------------------------------------

create table if not exists public.flocks (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  normalized_name text not null unique,
  leader_id uuid not null references auth.users(id),
  icon_id text not null default 'flock_paw_shield',
  bank_balance numeric(20,1) not null default 0 check (bank_balance >= 0),
  renamed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(name) between 3 and 24)
);

create table if not exists public.flock_members (
  flock_id uuid not null references public.flocks(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('leader','guard','member')),
  joined_at timestamptz not null default now(),
  primary key(flock_id, player_id)
);
create unique index if not exists one_leader_per_flock
  on public.flock_members(flock_id) where role='leader';

create table if not exists public.flock_applications (
  flock_id uuid not null references public.flocks(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','denied','cancelled')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users(id) on delete set null,
  primary key(flock_id, player_id)
);

create table if not exists public.flock_bank_ledger (
  id bigint generated always as identity primary key,
  flock_id uuid not null references public.flocks(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  amount numeric(20,1) not null check (amount <> 0),
  balance_after numeric(20,1) not null check (balance_after >= 0),
  reason text not null,
  source_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.flock_items (
  flock_id uuid not null references public.flocks(id) on delete cascade,
  item_id text not null,
  acquired_at timestamptz not null default now(),
  primary key(flock_id,item_id)
);

-- POIs and administration ----------------------------------------------------

create table if not exists public.game_pois (
  id uuid primary key default gen_random_uuid(),
  osm_type text,
  osm_id bigint,
  poi_type text not null check (poi_type in ('dog_park','pet_shop','veterinary','grooming','dog_wash')),
  name text,
  latitude double precision not null,
  longitude double precision not null,
  address text,
  opening_hours text,
  phone text,
  website text,
  has_game_shop boolean not null default false,
  source text not null default 'osm',
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique(osm_type,osm_id)
);

create table if not exists public.admin_users (
  player_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id) on delete set null
);

create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  admin_id uuid not null references auth.users(id),
  action text not null,
  target_player_id uuid references auth.users(id) on delete set null,
  target_object_id uuid,
  reason text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Indexes -------------------------------------------------------------------

create index if not exists world_bones_active_lat_lon_idx
  on public.world_bones(active,latitude,longitude);
create index if not exists dirt_piles_active_lat_lon_idx
  on public.dirt_piles(active,latitude,longitude);
create index if not exists presence_fresh_lat_lon_idx
  on public.player_presence(updated_at desc,latitude,longitude);
create index if not exists pois_active_lat_lon_idx
  on public.game_pois(active,latitude,longitude);
create index if not exists flock_members_player_idx
  on public.flock_members(player_id);
create index if not exists flock_applications_pending_idx
  on public.flock_applications(flock_id,created_at) where status='pending';
create index if not exists player_ledger_player_time_idx
  on public.player_bone_ledger(player_id,created_at desc);
create index if not exists flock_ledger_flock_time_idx
  on public.flock_bank_ledger(flock_id,created_at desc);

-- Private membership helpers prevent recursive flock_members RLS evaluation.
create or replace function private.is_flock_member(check_flock_id uuid, check_player_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(select 1 from public.flock_members fm
                where fm.flock_id=check_flock_id and fm.player_id=check_player_id)
$$;
create or replace function private.is_flock_officer(check_flock_id uuid, check_player_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(select 1 from public.flock_members fm
                where fm.flock_id=check_flock_id and fm.player_id=check_player_id
                  and fm.role in ('leader','guard'))
$$;
revoke all on function private.is_flock_member(uuid,uuid) from public,anon,authenticated;
revoke all on function private.is_flock_officer(uuid,uuid) from public,anon,authenticated;

-- RLS and grants -------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.world_bones enable row level security;
alter table public.dirt_piles enable row level security;
alter table public.player_presence enable row level security;
alter table public.bone_types enable row level security;
alter table public.pile_types enable row level security;
alter table public.shop_items enable row level security;
alter table public.player_bone_collection enable row level security;
alter table public.player_items enable row level security;
alter table public.player_settings enable row level security;
alter table public.distance_batches enable row level security;
alter table public.bone_collections enable row level security;
alter table public.bone_collection_rewards enable row level security;
alter table public.pile_claims enable row level security;
alter table public.home_slot_spins enable row level security;
alter table public.player_bone_ledger enable row level security;
alter table public.flocks enable row level security;
alter table public.flock_members enable row level security;
alter table public.flock_applications enable row level security;
alter table public.flock_bank_ledger enable row level security;
alter table public.flock_items enable row level security;
alter table public.game_pois enable row level security;
alter table public.admin_users enable row level security;
alter table public.admin_audit_log enable row level security;

-- Remove permissive prototype policies by exact known names.
drop policy if exists "profiles own read" on public.profiles;
drop policy if exists "profiles own update" on public.profiles;
drop policy if exists "world readable" on public.world_bones;
drop policy if exists "piles readable" on public.dirt_piles;
drop policy if exists "presence readable" on public.player_presence;
drop policy if exists "presence own" on public.player_presence;

create policy profiles_own_read on public.profiles for select to authenticated
  using ((select auth.uid())=id);
create policy world_bones_authenticated_read on public.world_bones for select to authenticated
  using (true);
create policy dirt_piles_authenticated_read on public.dirt_piles for select to authenticated
  using (true);
create policy bone_types_authenticated_read on public.bone_types for select to authenticated
  using (true);
create policy pile_types_authenticated_read on public.pile_types for select to authenticated
  using (true);
create policy shop_items_authenticated_read on public.shop_items for select to authenticated
  using (active);
create policy own_collection_read on public.player_bone_collection for select to authenticated
  using ((select auth.uid())=player_id);
create policy own_items_read on public.player_items for select to authenticated
  using ((select auth.uid())=player_id);
create policy own_settings_all on public.player_settings for all to authenticated
  using ((select auth.uid())=player_id) with check ((select auth.uid())=player_id);
create policy own_presence_write on public.player_presence for all to authenticated
  using ((select auth.uid())=player_id) with check ((select auth.uid())=player_id);
create policy fresh_presence_read on public.player_presence for select to authenticated
  using (updated_at > now()-interval '15 seconds');
create policy own_slot_spins_read on public.home_slot_spins for select to authenticated
  using ((select auth.uid())=player_id);
create policy own_ledger_read on public.player_bone_ledger for select to authenticated
  using ((select auth.uid())=player_id);
create policy public_flock_list_read on public.flocks for select to authenticated
  using (true);
create policy own_flock_memberships_read on public.flock_members for select to authenticated
  using (private.is_flock_member(flock_id,(select auth.uid())));
create policy own_flock_applications_read on public.flock_applications for select to authenticated
  using (player_id=(select auth.uid()) or private.is_flock_officer(flock_id,(select auth.uid())));
create policy member_flock_ledger_read on public.flock_bank_ledger for select to authenticated
  using (private.is_flock_member(flock_id,(select auth.uid())));
create policy member_flock_items_read on public.flock_items for select to authenticated
  using (private.is_flock_member(flock_id,(select auth.uid())));
create policy active_pois_read on public.game_pois for select to authenticated using (active);

revoke all on all tables in schema public from anon;
revoke insert, update, delete on all tables in schema public from authenticated;
grant usage on schema public to authenticated;
grant select on public.profiles, public.world_bones, public.dirt_piles,
  public.player_presence, public.bone_types, public.pile_types, public.shop_items,
  public.player_bone_collection, public.player_items, public.player_settings,
  public.home_slot_spins, public.player_bone_ledger, public.flocks,
  public.flock_members, public.flock_applications, public.flock_bank_ledger,
  public.flock_items, public.game_pois to authenticated;
grant insert,update,delete on public.player_presence,public.player_settings to authenticated;

-- Realtime tables. Supabase may already contain these publications.
do $$ begin
  alter publication supabase_realtime add table public.world_bones;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.dirt_piles;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.player_presence;
exception when duplicate_object then null; end $$;
