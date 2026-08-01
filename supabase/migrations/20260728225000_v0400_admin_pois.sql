-- FBQ 0.400: server-assigned administration, audit log and dog-related POIs.

create or replace function private.is_admin(check_player_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.admin_users a where a.player_id=check_player_id) $$;

create or replace function private.assert_admin(check_player_id uuid)
returns void language plpgsql stable security definer set search_path=''
as $$
begin
  if check_player_id is null or not private.is_admin(check_player_id) then
    raise exception 'ADMIN_REQUIRED' using errcode='42501';
  end if;
end $$;

create or replace function private.require_admin_reason(raw_reason text)
returns text language plpgsql immutable set search_path=''
as $$
declare result text:=trim(regexp_replace(coalesce(raw_reason,''),'\s+',' ','g'));
begin
  if char_length(result)<3 or char_length(result)>500 then
    raise exception 'ADMIN_REASON_REQUIRED' using errcode='22023';
  end if;
  return result;
end $$;

revoke all on function private.is_admin(uuid) from public,anon,authenticated;
revoke all on function private.assert_admin(uuid) from public,anon,authenticated;
revoke all on function private.require_admin_reason(text) from public,anon,authenticated;
revoke select on public.admin_users,public.admin_audit_log from authenticated;

create or replace function public.get_session_bootstrap()
returns table(
  player_id uuid,display_name text,onboarding_complete boolean,bone_count bigint,
  total_meters bigint,total_bones bigint,total_piles bigint,active_marker_id text,
  home_lat double precision,home_lon double precision,home_changed_at timestamptz,
  walking_mode_enabled boolean,bark_enabled boolean,vibration_enabled boolean,
  is_admin boolean,is_suspended boolean,requires_new_name boolean,created_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  return query select p.id,p.display_name,p.onboarding_complete,p.bone_count,
    p.total_meters,p.total_bones,p.total_piles,p.active_marker_id,
    p.home_lat,p.home_lon,p.home_changed_at,p.walking_mode_enabled,p.bark_enabled,p.vibration_enabled,
    private.is_admin(uid),
    (p.suspended_permanently or p.suspended_until>now()),p.requires_new_name,p.created_at
  from public.profiles p where p.id=uid and p.deleted_at is null;
end $$;

create or replace function public.list_map_pois(
  min_lat double precision,min_lon double precision,
  max_lat double precision,max_lon double precision
) returns table(
  poi_id uuid,poi_type text,name text,latitude double precision,longitude double precision,
  address text,opening_hours text,phone text,website text,has_game_shop boolean
) language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  if min_lat not between -90 and 90 or max_lat not between -90 and 90
     or min_lon not between -180 and 180 or max_lon not between -180 and 180
     or min_lat>max_lat or min_lon>max_lon
     or max_lat-min_lat>20 or max_lon-min_lon>20 then
    raise exception 'INVALID_MAP_BOUNDS' using errcode='22023';
  end if;
  return query select p.id,p.poi_type,p.name,p.latitude,p.longitude,p.address,
    p.opening_hours,p.phone,p.website,p.has_game_shop
  from public.game_pois p where p.active and p.latitude between min_lat and max_lat
    and p.longitude between min_lon and max_lon order by p.poi_type,p.id limit 5000;
end $$;

create or replace function public.list_nearby_players()
returns table(
  player_id uuid,latitude double precision,longitude double precision,
  heading real,marker_id text,shared_flock_ids uuid[]
) language plpgsql stable security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); me public.player_presence%rowtype;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  select * into me from public.player_presence where player_presence.player_id=uid;
  if not found or me.updated_at<now()-interval '15 seconds' then return; end if;
  return query
  select pp.player_id,pp.latitude,pp.longitude,pp.heading,p.active_marker_id,
    coalesce((select array_agg(mine.flock_id order by mine.flock_id)
      from public.flock_members mine join public.flock_members theirs on theirs.flock_id=mine.flock_id
      where mine.player_id=uid and theirs.player_id=pp.player_id),'{}'::uuid[])
  from public.player_presence pp join public.profiles p on p.id=pp.player_id
  where pp.player_id<>uid and pp.updated_at>=now()-interval '15 seconds'
    and pp.accuracy_m<=30 and p.deleted_at is null and not p.suspended_permanently
    and (p.suspended_until is null or p.suspended_until<=now())
    and private.distance_meters(me.latitude,me.longitude,pp.latitude,pp.longitude)<=200
  order by pp.player_id;
end $$;

create or replace function public.admin_search_players(p_search text default null)
returns table(
  player_id uuid,display_name text,bone_count bigint,is_suspended boolean,
  requires_new_name boolean,created_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); needle text:=lower(trim(coalesce(p_search,'')));
begin
  perform private.assert_admin(uid);
  return query select p.id,p.display_name,p.bone_count,
    (p.suspended_permanently or p.suspended_until>now()),p.requires_new_name,p.created_at
  from public.profiles p where p.deleted_at is null
    and (needle='' or lower(p.display_name) like '%'||needle||'%' or p.id::text=needle)
  order by lower(p.display_name),p.id limit 100;
end $$;

create or replace function public.admin_adjust_bones(
  p_player_id uuid,p_amount bigint,p_reason text
) returns bigint language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text; new_balance bigint;
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  if p_amount=0 or abs(p_amount)>1000000000 then raise exception 'INVALID_BONE_ADJUSTMENT' using errcode='22023'; end if;
  select bone_count into new_balance from public.profiles where id=p_player_id and deleted_at is null for update;
  if not found then raise exception 'PLAYER_NOT_FOUND' using errcode='P0001'; end if;
  if new_balance+p_amount<0 then raise exception 'BALANCE_CANNOT_BE_NEGATIVE' using errcode='P0001'; end if;
  update public.profiles set bone_count=bone_count+p_amount,updated_at=now()
  where id=p_player_id returning bone_count into new_balance;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason)
  values(p_player_id,p_amount,new_balance,'admin_adjustment: '||reason);
  insert into public.admin_audit_log(admin_id,action,target_player_id,reason,details)
  values(uid,'adjust_bones',p_player_id,reason,jsonb_build_object('amount',p_amount,'balance_after',new_balance));
  return new_balance;
end $$;

create or replace function public.admin_set_player_item(
  p_player_id uuid,p_item_id text,p_grant boolean,p_reason text
) returns boolean language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text;
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  if not exists(select 1 from public.shop_items where id=p_item_id) then
    raise exception 'SHOP_ITEM_NOT_FOUND' using errcode='P0001';
  end if;
  if p_grant then
    insert into public.player_items(player_id,item_id,acquisition_source)
    values(p_player_id,p_item_id,'admin') on conflict do nothing;
  else
    if p_item_id='marker_default_paw' then raise exception 'DEFAULT_ITEM_CANNOT_BE_REMOVED' using errcode='P0001'; end if;
    delete from public.player_items where player_id=p_player_id and item_id=p_item_id;
    update public.profiles set active_marker_id='marker_default_paw',updated_at=now()
    where id=p_player_id and active_marker_id=p_item_id;
  end if;
  insert into public.admin_audit_log(admin_id,action,target_player_id,reason,details)
  values(uid,case when p_grant then 'grant_item' else 'remove_item' end,p_player_id,reason,
    jsonb_build_object('item_id',p_item_id));
  return p_grant;
end $$;

create or replace function public.admin_grant_entitlement(
  p_player_id uuid,p_item_id text,p_reason text
) returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text;
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  insert into public.player_entitlements(player_id,item_id,reason)
  values(p_player_id,p_item_id,reason) on conflict(player_id,item_id) do update set
    reason=excluded.reason,granted_at=now();
  insert into public.player_items(player_id,item_id,acquisition_source)
  values(p_player_id,p_item_id,'entitlement') on conflict do nothing;
  insert into public.admin_audit_log(admin_id,action,target_player_id,reason,details)
  values(uid,'grant_entitlement',p_player_id,reason,jsonb_build_object('item_id',p_item_id));
end $$;

create or replace function public.admin_force_player_name(
  p_player_id uuid,p_new_name text,p_require_new_name boolean,p_reason text
) returns text language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text; normalized text;
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  normalized:=private.normalize_game_name(p_new_name);
  if not private.valid_player_name(normalized) then raise exception 'INVALID_PLAYER_NAME' using errcode='22023'; end if;
  update public.profiles set display_name=normalized,requires_new_name=p_require_new_name,
    name_changed_at=null,updated_at=now() where id=p_player_id and deleted_at is null;
  if not found then raise exception 'PLAYER_NOT_FOUND' using errcode='P0001'; end if;
  insert into public.admin_audit_log(admin_id,action,target_player_id,reason,details)
  values(uid,'force_player_name',p_player_id,reason,
    jsonb_build_object('new_name',normalized,'requires_new_name',p_require_new_name));
  return normalized;
end $$;

create or replace function public.admin_force_flock_name(
  p_flock_id uuid,p_new_name text,p_reason text
) returns text language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text; normalized text;
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  normalized:=private.normalize_flock_name(p_new_name);
  if not private.valid_flock_name(normalized) then raise exception 'INVALID_FLOCK_NAME' using errcode='22023'; end if;
  update public.flocks set name=normalized,normalized_name=lower(normalized),renamed_at=null,updated_at=now()
  where id=p_flock_id;
  if not found then raise exception 'FLOCK_NOT_FOUND' using errcode='P0001'; end if;
  insert into public.admin_audit_log(admin_id,action,target_object_id,reason,details)
  values(uid,'force_flock_name',p_flock_id,reason,jsonb_build_object('new_name',normalized));
  return normalized;
exception when unique_violation then raise exception 'FLOCK_NAME_TAKEN' using errcode='23505';
end $$;

create or replace function public.admin_set_suspension(
  p_player_id uuid,p_permanent boolean,p_until timestamptz,p_reason text
) returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text;
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  if p_player_id=uid then raise exception 'ADMIN_CANNOT_SUSPEND_SELF' using errcode='P0001'; end if;
  if not p_permanent and (p_until is null or p_until<=now()) then
    raise exception 'INVALID_SUSPENSION_END' using errcode='22023';
  end if;
  update public.profiles set suspended_permanently=p_permanent,
    suspended_until=case when p_permanent then null else p_until end,
    suspension_reason=reason,updated_at=now() where id=p_player_id and deleted_at is null;
  if not found then raise exception 'PLAYER_NOT_FOUND' using errcode='P0001'; end if;
  insert into public.admin_audit_log(admin_id,action,target_player_id,reason,details)
  values(uid,'suspend_player',p_player_id,reason,
    jsonb_build_object('permanent',p_permanent,'until',p_until));
end $$;

create or replace function public.admin_clear_suspension(p_player_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text;
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  update public.profiles set suspended_permanently=false,suspended_until=null,
    suspension_reason=null,updated_at=now() where id=p_player_id and deleted_at is null;
  if not found then raise exception 'PLAYER_NOT_FOUND' using errcode='P0001'; end if;
  insert into public.admin_audit_log(admin_id,action,target_player_id,reason)
  values(uid,'clear_suspension',p_player_id,reason);
end $$;

create or replace function public.admin_upsert_poi(
  p_poi_id uuid,p_poi_type text,p_name text,p_latitude double precision,
  p_longitude double precision,p_address text,p_opening_hours text,p_phone text,
  p_website text,p_has_game_shop boolean,p_reason text
) returns uuid language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text; result uuid:=coalesce(p_poi_id,gen_random_uuid());
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  if p_poi_type not in ('dog_park','pet_shop','veterinary','grooming','dog_wash')
     or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'INVALID_POI' using errcode='22023';
  end if;
  insert into public.game_pois(id,poi_type,name,latitude,longitude,address,opening_hours,
    phone,website,has_game_shop,source,active,updated_at)
  values(result,p_poi_type,nullif(trim(p_name),''),p_latitude,p_longitude,p_address,
    p_opening_hours,p_phone,p_website,p_has_game_shop,'admin',true,now())
  on conflict(id) do update set poi_type=excluded.poi_type,name=excluded.name,
    latitude=excluded.latitude,longitude=excluded.longitude,address=excluded.address,
    opening_hours=excluded.opening_hours,phone=excluded.phone,website=excluded.website,
    has_game_shop=excluded.has_game_shop,active=true,updated_at=now();
  insert into public.admin_audit_log(admin_id,action,target_object_id,reason,details)
  values(uid,case when p_poi_id is null then 'create_poi' else 'update_poi' end,result,reason,
    jsonb_build_object('poi_type',p_poi_type,'latitude',p_latitude,'longitude',p_longitude,
      'has_game_shop',p_has_game_shop));
  return result;
end $$;

create or replace function public.admin_delete_poi(p_poi_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text;
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  update public.game_pois set active=false,updated_at=now() where id=p_poi_id;
  if not found then raise exception 'POI_NOT_FOUND' using errcode='P0001'; end if;
  insert into public.admin_audit_log(admin_id,action,target_object_id,reason)
  values(uid,'delete_poi',p_poi_id,reason);
end $$;

create or replace function public.admin_upsert_world_object(
  p_object_id uuid,p_object_type text,p_latitude double precision,
  p_longitude double precision,p_variant integer,p_reason text
) returns uuid language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text; result uuid:=coalesce(p_object_id,gen_random_uuid());
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  if p_object_type not in ('bone','pile') or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180 then raise exception 'INVALID_WORLD_OBJECT' using errcode='22023'; end if;
  if p_object_type='bone' then
    if p_variant not between 0 and 11 then raise exception 'INVALID_BONE_TYPE' using errcode='22023'; end if;
    insert into public.world_bones(id,latitude,longitude,bone_type,active,placed_by,placement_source,updated_at)
    values(result,p_latitude,p_longitude,p_variant,true,uid,'admin',now())
    on conflict(id) do update set latitude=excluded.latitude,longitude=excluded.longitude,
      bone_type=excluded.bone_type,active=true,placed_by=uid,placement_source='admin',updated_at=now();
    -- Changing an object's class leaves its historical row intact but inactive.
    update public.dirt_piles set active=false,respawn_at=null,updated_at=now() where id=result;
  else
    if p_variant not between 0 and 4 then raise exception 'INVALID_PILE_TYPE' using errcode='22023'; end if;
    insert into public.dirt_piles(id,latitude,longitude,pile_type,cost,active,placed_by,placement_source,updated_at)
    select result,p_latitude,p_longitude,t.id,t.cost,true,uid,'admin',now()
      from public.pile_types t where t.id=p_variant
    on conflict(id) do update set latitude=excluded.latitude,longitude=excluded.longitude,
      pile_type=excluded.pile_type,cost=excluded.cost,active=true,placed_by=uid,
      placement_source='admin',updated_at=now();
    update public.world_bones set active=false,respawn_at=null,updated_at=now() where id=result;
  end if;
  insert into public.admin_audit_log(admin_id,action,target_object_id,reason,details)
  values(uid,case when p_object_id is null then 'create_world_object' else 'update_world_object' end,
    result,reason,jsonb_build_object('type',p_object_type,'variant',p_variant,
      'latitude',p_latitude,'longitude',p_longitude));
  return result;
end $$;

create or replace function public.admin_delete_world_object(
  p_object_id uuid,p_object_type text,p_reason text
) returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text; changed integer;
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  if p_object_type='bone' then
    update public.world_bones set active=false,respawn_at=null,updated_at=now() where id=p_object_id;
  elsif p_object_type='pile' then
    update public.dirt_piles set active=false,respawn_at=null,updated_at=now() where id=p_object_id;
  else raise exception 'INVALID_WORLD_OBJECT' using errcode='22023'; end if;
  get diagnostics changed=row_count;
  if changed=0 then raise exception 'WORLD_OBJECT_NOT_FOUND' using errcode='P0001'; end if;
  insert into public.admin_audit_log(admin_id,action,target_object_id,reason,details)
  values(uid,'delete_world_object',p_object_id,reason,jsonb_build_object('type',p_object_type));
end $$;

create or replace function public.admin_get_audit_log(p_limit integer default 100)
returns table(
  entry_id bigint,admin_id uuid,action text,target_player_id uuid,
  target_object_id uuid,reason text,details jsonb,created_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
begin
  perform private.assert_admin(auth.uid());
  return query select a.id,a.admin_id,a.action,a.target_player_id,a.target_object_id,
    a.reason,a.details,a.created_at from public.admin_audit_log a
    order by a.created_at desc,a.id desc limit least(greatest(coalesce(p_limit,100),1),500);
end $$;

-- Explicit API permissions.
revoke execute on function public.get_session_bootstrap() from public,anon;
revoke execute on function public.list_map_pois(double precision,double precision,double precision,double precision) from public,anon;
revoke execute on function public.list_nearby_players() from public,anon;
revoke execute on function public.admin_search_players(text) from public,anon;
revoke execute on function public.admin_adjust_bones(uuid,bigint,text) from public,anon;
revoke execute on function public.admin_set_player_item(uuid,text,boolean,text) from public,anon;
revoke execute on function public.admin_grant_entitlement(uuid,text,text) from public,anon;
revoke execute on function public.admin_force_player_name(uuid,text,boolean,text) from public,anon;
revoke execute on function public.admin_force_flock_name(uuid,text,text) from public,anon;
revoke execute on function public.admin_set_suspension(uuid,boolean,timestamptz,text) from public,anon;
revoke execute on function public.admin_clear_suspension(uuid,text) from public,anon;
revoke execute on function public.admin_upsert_poi(uuid,text,text,double precision,double precision,text,text,text,text,boolean,text) from public,anon;
revoke execute on function public.admin_delete_poi(uuid,text) from public,anon;
revoke execute on function public.admin_upsert_world_object(uuid,text,double precision,double precision,integer,text) from public,anon;
revoke execute on function public.admin_delete_world_object(uuid,text,text) from public,anon;
revoke execute on function public.admin_get_audit_log(integer) from public,anon;

grant execute on function public.get_session_bootstrap() to authenticated;
grant execute on function public.list_map_pois(double precision,double precision,double precision,double precision) to authenticated;
grant execute on function public.list_nearby_players() to authenticated;
grant execute on function public.admin_search_players(text) to authenticated;
grant execute on function public.admin_adjust_bones(uuid,bigint,text) to authenticated;
grant execute on function public.admin_set_player_item(uuid,text,boolean,text) to authenticated;
grant execute on function public.admin_grant_entitlement(uuid,text,text) to authenticated;
grant execute on function public.admin_force_player_name(uuid,text,boolean,text) to authenticated;
grant execute on function public.admin_force_flock_name(uuid,text,text) to authenticated;
grant execute on function public.admin_set_suspension(uuid,boolean,timestamptz,text) to authenticated;
grant execute on function public.admin_clear_suspension(uuid,text) to authenticated;
grant execute on function public.admin_upsert_poi(uuid,text,text,double precision,double precision,text,text,text,text,boolean,text) to authenticated;
grant execute on function public.admin_delete_poi(uuid,text) to authenticated;
grant execute on function public.admin_upsert_world_object(uuid,text,double precision,double precision,integer,text) to authenticated;
grant execute on function public.admin_delete_world_object(uuid,text,text) to authenticated;
grant execute on function public.admin_get_audit_log(integer) to authenticated;
