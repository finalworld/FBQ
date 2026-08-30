-- Fix two nullable/encoding bugs found during physical 0.400 testing and add
-- the walking incentive. Walking rewards deliberately do not touch flock
-- ledgers; only loose world-bone collection contributes to flock banks.

alter table public.profiles
  add column if not exists walking_reward_remainder integer not null default 0
    check (walking_reward_remainder between 0 and 2999);

create or replace function public.equip_marker(p_item_id text)
returns text language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  if not exists(
    select 1 from public.player_items pi
    join public.shop_items i on i.id=pi.item_id
    where pi.player_id=uid and pi.item_id=p_item_id and i.active
      and i.id like 'marker_%'
  ) then
    raise exception 'MARKER_NOT_OWNED' using errcode='42501';
  end if;
  update public.profiles set active_marker_id=p_item_id,updated_at=now() where id=uid;
  return p_item_id;
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
    coalesce(p.suspended_permanently,false) or coalesce(p.suspended_until>now(),false),
    coalesce(p.requires_new_name,false),p.created_at
  from public.profiles p where p.deleted_at is null
    and (needle='' or lower(p.display_name) like '%'||needle||'%' or p.id::text=needle)
  order by lower(p.display_name),p.id limit 100;
end $$;

create or replace function public.add_distance_batch(
  client_batch_id uuid, meters integer,
  sample_started_at timestamptz, sample_ended_at timestamptz
) returns bigint language plpgsql security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid(); result bigint; elapsed_seconds double precision;
  maximum_plausible_meters integer; accepted boolean; combined integer;
  reward integer; new_balance bigint;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  elapsed_seconds:=extract(epoch from (sample_ended_at-sample_started_at));
  maximum_plausible_meters:=ceil(greatest(elapsed_seconds,0)*3.34+50)::integer;
  if meters<0 or meters>200000 or sample_ended_at<sample_started_at
     or sample_ended_at-sample_started_at>interval '2 hours'
     or sample_ended_at>now()+interval '5 minutes'
     or sample_started_at<now()-interval '3 hours'
     or meters>maximum_plausible_meters then
    raise exception 'INVALID_DISTANCE_BATCH' using errcode='22023';
  end if;

  insert into public.distance_batches(player_id,client_batch_id,meters,sample_started_at,sample_ended_at)
  values(uid,client_batch_id,meters,sample_started_at,sample_ended_at)
  on conflict on constraint distance_batches_player_id_client_batch_id_key do nothing;
  accepted:=found;

  if accepted then
    select walking_reward_remainder+meters into combined
      from public.profiles where id=uid for update;
    reward:=combined/3000;
    update public.profiles
      set total_meters=total_meters+meters,
          walking_reward_remainder=combined%3000,
          bone_count=bone_count+reward,
          updated_at=now()
      where id=uid returning total_meters,bone_count into result,new_balance;
    if reward>0 then
      insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
      values(uid,reward,new_balance,'walking_reward',client_batch_id);
    end if;
  else
    select total_meters into result from public.profiles where id=uid;
  end if;
  return result;
end $$;

revoke execute on function public.equip_marker(text) from public,anon;
revoke execute on function public.admin_search_players(text) from public,anon;
revoke execute on function public.add_distance_batch(uuid,integer,timestamptz,timestamptz) from public,anon;
grant execute on function public.equip_marker(text) to authenticated;
grant execute on function public.admin_search_players(text) to authenticated;
grant execute on function public.add_distance_batch(uuid,integer,timestamptz,timestamptz) to authenticated;
