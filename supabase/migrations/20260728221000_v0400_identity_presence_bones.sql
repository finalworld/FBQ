-- FBQ 0.400: identity, profile, presence, distance and loose-bone collection.
-- Every exposed mutation derives the player from auth.uid().

-- Remove the prototype trigger that forced collected objects back to active.
do $cleanup$
declare trigger_name text;
begin
  for trigger_name in
    select t.tgname
    from pg_trigger t
    join pg_proc p on p.oid=t.tgfoid
    where not t.tgisinternal
      and p.proname='keep_respawning_items_active'
      and t.tgrelid in ('public.world_bones'::regclass,'public.dirt_piles'::regclass)
  loop
    execute format('drop trigger if exists %I on public.world_bones',trigger_name);
    execute format('drop trigger if exists %I on public.dirt_piles',trigger_name);
  end loop;
end $cleanup$;
drop function if exists public.keep_respawning_items_active() cascade;

-- The prototype RPC return type/signature varied during manual setup. Drop all
-- overloads by identity before creating the locked 0.400 contract.
do $cleanup$
declare proc regprocedure;
begin
  for proc in
    select p.oid::regprocedure from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='collect_nearby_bones'
  loop execute format('drop function %s cascade',proc); end loop;
end $cleanup$;

create or replace function private.normalize_game_name(raw_name text)
returns text language sql immutable set search_path=''
as $$
  select trim(regexp_replace(coalesce(raw_name,''),'\s+',' ','g'))
$$;

create or replace function private.valid_player_name(raw_name text)
returns boolean language sql immutable set search_path=''
as $$
  select char_length(private.normalize_game_name(raw_name)) between 3 and 20
     and private.normalize_game_name(raw_name) ~ '^[[:alnum:]åäöÅÄÖ ]+$'
$$;

create or replace function private.distance_meters(
  lat1 double precision, lon1 double precision,
  lat2 double precision, lon2 double precision
) returns double precision language sql immutable strict set search_path=''
as $$
  select 6371000.0 * 2.0 * asin(
    least(1.0,sqrt(
      power(sin(radians(lat2-lat1)/2.0),2) +
      cos(radians(lat1))*cos(radians(lat2))*
      power(sin(radians(lon2-lon1)/2.0),2)
    ))
  )
$$;

create or replace function private.assert_active_player(player uuid)
returns void language plpgsql stable security definer set search_path=''
as $$
declare p public.profiles%rowtype;
begin
  select * into p from public.profiles where id=player and deleted_at is null;
  if not found then raise exception 'PROFILE_REQUIRED' using errcode='P0001'; end if;
  if p.suspended_permanently or p.suspended_until > now() then
    raise exception 'PLAYER_SUSPENDED' using errcode='P0001';
  end if;
end $$;

revoke all on function private.normalize_game_name(text) from public,anon,authenticated;
revoke all on function private.valid_player_name(text) from public,anon,authenticated;
revoke all on function private.distance_meters(double precision,double precision,double precision,double precision) from public,anon,authenticated;
revoke all on function private.assert_active_player(uuid) from public,anon,authenticated;

-- New Google users receive private state and the free default marker.
create or replace function public.create_player_profile()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  insert into public.profiles(id,display_name,onboarding_complete,created_at,updated_at)
  values(new.id,'Frassevän',false,now(),now()) on conflict(id) do nothing;
  insert into public.player_settings(player_id) values(new.id) on conflict do nothing;
  insert into public.player_items(player_id,item_id,acquisition_source)
  values(new.id,'marker_default_paw','default') on conflict do nothing;
  insert into public.player_bone_collection(player_id,bone_type,lifetime_count)
  select new.id,b.id,0 from public.bone_types b on conflict do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.create_player_profile();
revoke all on function public.create_player_profile() from public,anon,authenticated;

-- Backfill auxiliary state for users created by the 0.300 trigger.
insert into public.player_settings(player_id)
select p.id from public.profiles p on conflict do nothing;
insert into public.player_items(player_id,item_id,acquisition_source)
select p.id,'marker_default_paw','default' from public.profiles p on conflict do nothing;
insert into public.player_bone_collection(player_id,bone_type,lifetime_count)
select p.id,b.id,0 from public.profiles p cross join public.bone_types b on conflict do nothing;

create or replace function public.complete_profile(player_name text)
returns table(display_name text, onboarding_complete boolean)
language plpgsql security definer set search_path=''
as $$
declare uid uuid := auth.uid(); normalized text;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  normalized := private.normalize_game_name(player_name);
  if not private.valid_player_name(normalized) then
    raise exception 'INVALID_PLAYER_NAME' using errcode='22023';
  end if;
  update public.profiles set display_name=normalized,onboarding_complete=true,
    requires_new_name=false,name_changed_at=now(),updated_at=now()
  where id=uid and deleted_at is null
  returning profiles.display_name,profiles.onboarding_complete
  into display_name,onboarding_complete;
  if not found then raise exception 'PROFILE_REQUIRED' using errcode='P0001'; end if;
  return next;
end $$;

create or replace function public.change_display_name(player_name text)
returns table(display_name text, next_change_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare uid uuid := auth.uid(); normalized text; last_change timestamptz;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  normalized := private.normalize_game_name(player_name);
  if not private.valid_player_name(normalized) then
    raise exception 'INVALID_PLAYER_NAME' using errcode='22023';
  end if;
  select name_changed_at into last_change from public.profiles
  where id=uid and deleted_at is null for update;
  if not found then raise exception 'PROFILE_REQUIRED' using errcode='P0001'; end if;
  if last_change is not null and last_change+interval '24 hours'>now() then
    raise exception 'NAME_COOLDOWN' using errcode='P0001',
      detail=(last_change+interval '24 hours')::text;
  end if;
  update public.profiles set display_name=normalized,name_changed_at=now(),
    requires_new_name=false,updated_at=now() where id=uid;
  display_name:=normalized; next_change_at:=now()+interval '24 hours'; return next;
end $$;

create or replace function public.update_presence(
  latitude double precision, longitude double precision, accuracy_m real,
  heading real default 0, speed_mps real default null,
  is_background boolean default false
) returns timestamptz language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); stamp timestamptz:=clock_timestamp();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  if latitude not between -90 and 90 or longitude not between -180 and 180
     or accuracy_m<=0 or accuracy_m>10000 then
    raise exception 'INVALID_LOCATION' using errcode='22023';
  end if;
  insert into public.player_presence
    (player_id,latitude,longitude,accuracy_m,heading,speed_mps,is_background,moved_at,updated_at)
  values(uid,latitude,longitude,accuracy_m,coalesce(heading,0),speed_mps,is_background,stamp,stamp)
  on conflict(player_id) do update set
    latitude=excluded.latitude,longitude=excluded.longitude,
    accuracy_m=excluded.accuracy_m,heading=excluded.heading,
    speed_mps=excluded.speed_mps,is_background=excluded.is_background,
    moved_at=case when private.distance_meters(
      public.player_presence.latitude,public.player_presence.longitude,
      excluded.latitude,excluded.longitude)>2 then stamp
      else public.player_presence.moved_at end,
    updated_at=stamp;
  return stamp;
end $$;

create or replace function public.add_distance_batch(
  client_batch_id uuid, meters integer,
  sample_started_at timestamptz, sample_ended_at timestamptz
) returns bigint language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); result bigint;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  if meters<0 or meters>200000 or sample_ended_at<sample_started_at
     or sample_ended_at-sample_started_at>interval '2 hours'
     or sample_ended_at>now()+interval '5 minutes'
     or sample_started_at<now()-interval '3 hours' then
    raise exception 'INVALID_DISTANCE_BATCH' using errcode='22023';
  end if;
  insert into public.distance_batches(player_id,client_batch_id,meters,sample_started_at,sample_ended_at)
  values(uid,client_batch_id,meters,sample_started_at,sample_ended_at)
  on conflict(player_id,client_batch_id) do nothing;
  if found then
    update public.profiles set total_meters=total_meters+meters,updated_at=now()
    where id=uid;
  end if;
  select total_meters into result from public.profiles where id=uid;
  return result;
end $$;

create or replace function public.collect_nearby_bones()
returns table(
  collection_id uuid, bone_type smallint, bone_value integer,
  bones_collected integer, rewarded_players integer,
  player_reward bigint, player_balance bigint
) language plpgsql security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid(); me public.player_presence%rowtype;
  wb public.world_bones%rowtype; bt public.bone_types%rowtype;
  recipient record; membership record; cid uuid;
  reward_count integer; own_reward bigint:=0; collected_count integer:=0;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  select * into me from public.player_presence where player_id=uid for update;
  if not found or me.updated_at<now()-interval '15 seconds' or me.accuracy_m>30 then
    raise exception 'ACCURATE_LOCATION_REQUIRED' using errcode='P0001';
  end if;

  for wb in
    select w.* from public.world_bones w
    where w.active and private.distance_meters(me.latitude,me.longitude,w.latitude,w.longitude)<=25
    order by w.created_at,w.id for update skip locked
  loop
    select * into bt from public.bone_types where id=wb.bone_type;
    update public.world_bones set active=false,collected_at=now(),
      respawn_at=now()+interval '5 minutes',updated_at=now() where id=wb.id;
    insert into public.bone_collections
      (world_bone_id,world_generation,initiator_id,bone_type,bone_value)
    values(wb.id,wb.generation,uid,wb.bone_type,bt.value) returning id into cid;
    reward_count:=0;

    for recipient in
      select pp.player_id,
        private.distance_meters(pp.latitude,pp.longitude,wb.latitude,wb.longitude) as distance_m
      from public.player_presence pp
      join public.profiles p on p.id=pp.player_id
      where pp.updated_at>=now()-interval '15 seconds' and pp.accuracy_m<=30
        and not p.suspended_permanently
        and (p.suspended_until is null or p.suspended_until<=now())
        and p.deleted_at is null
        and private.distance_meters(pp.latitude,pp.longitude,wb.latitude,wb.longitude)<=25
      order by pp.player_id
    loop
      insert into public.bone_collection_rewards(collection_id,player_id,distance_m)
      values(cid,recipient.player_id,recipient.distance_m) on conflict do nothing;
      if found then
        update public.profiles set bone_count=bone_count+bt.value,
          total_bones=total_bones+1,updated_at=now()
        where id=recipient.player_id;
        insert into public.player_bone_collection
          (player_id,bone_type,lifetime_count,first_discovered_at,updated_at)
        values(recipient.player_id,wb.bone_type,1,now(),now())
        on conflict(player_id,bone_type) do update set
          lifetime_count=public.player_bone_collection.lifetime_count+1,
          first_discovered_at=coalesce(public.player_bone_collection.first_discovered_at,now()),
          updated_at=now();
        insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
        select recipient.player_id,bt.value,p.bone_count,'loose_bone',cid
        from public.profiles p where p.id=recipient.player_id;

        for membership in select fm.flock_id from public.flock_members fm
          where fm.player_id=recipient.player_id order by fm.flock_id
        loop
          update public.flocks set bank_balance=bank_balance+(bt.value::numeric/10),updated_at=now()
          where id=membership.flock_id;
          insert into public.flock_bank_ledger(flock_id,actor_id,amount,balance_after,reason,source_id)
          select membership.flock_id,recipient.player_id,bt.value::numeric/10,
            f.bank_balance,'loose_bone_bonus',cid from public.flocks f where f.id=membership.flock_id;
        end loop;
        reward_count:=reward_count+1;
        if recipient.player_id=uid then own_reward:=own_reward+bt.value; end if;
      end if;
    end loop;
    collection_id:=cid; bone_type:=wb.bone_type; bone_value:=bt.value;
    bones_collected:=1; rewarded_players:=reward_count; player_reward:=own_reward;
    select p.bone_count into player_balance from public.profiles p where p.id=uid;
    return next;
    collected_count:=collected_count+1;
  end loop;
  if collected_count=0 then
    raise exception 'NO_BONES_IN_RANGE' using errcode='P0001';
  end if;
end $$;

-- API function permissions are explicit.
revoke execute on function public.complete_profile(text) from public,anon;
revoke execute on function public.change_display_name(text) from public,anon;
revoke execute on function public.update_presence(double precision,double precision,real,real,real,boolean) from public,anon;
revoke execute on function public.add_distance_batch(uuid,integer,timestamptz,timestamptz) from public,anon;
revoke execute on function public.collect_nearby_bones() from public,anon;
grant execute on function public.complete_profile(text) to authenticated;
grant execute on function public.change_display_name(text) to authenticated;
grant execute on function public.update_presence(double precision,double precision,real,real,real,boolean) to authenticated;
grant execute on function public.add_distance_batch(uuid,integer,timestamptz,timestamptz) to authenticated;
grant execute on function public.collect_nearby_bones() to authenticated;

-- Presence must pass the validation and suspension checks in update_presence().
revoke insert,update,delete on public.player_presence from authenticated;
