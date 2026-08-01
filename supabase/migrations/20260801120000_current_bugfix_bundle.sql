-- Current mobile bug-fix bundle: accurate flock contribution totals and
-- explicit realtime publication for player balances and map objects.

create or replace function public.get_flock_contribution_leaderboard(p_flock_id uuid)
returns table(player_id uuid,display_name text,total_contributed bigint)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not private.is_flock_member(p_flock_id,auth.uid()) then
    raise exception 'FLOCK_MEMBER_REQUIRED' using errcode='42501';
  end if;
  return query
    select m.player_id,coalesce(p.display_name,'Borttagen spelare'),
      coalesce(floor(sum(greatest(l.amount,0))),0)::bigint
    from public.flock_members m
    left join public.profiles p on p.id=m.player_id
    left join public.flock_bank_ledger l
      on l.flock_id=m.flock_id and l.actor_id=m.player_id and l.amount>0
    where m.flock_id=p_flock_id
    group by m.player_id,p.display_name
    order by coalesce(floor(sum(greatest(l.amount,0))),0) desc,
      lower(coalesce(p.display_name,'')),m.player_id;
end $$;

revoke execute on function public.get_flock_contribution_leaderboard(uuid) from public,anon;
grant execute on function public.get_flock_contribution_leaderboard(uuid) to authenticated;

-- Reinstall the admin RPCs with null-safe output and an explicit scalar result.
-- This also repairs projects that received an older v0.400 function body.
create or replace function public.admin_search_players(p_search text default null)
returns table(
  player_id uuid, display_name text, bone_count bigint, is_suspended boolean,
  requires_new_name boolean, created_at timestamptz
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

create or replace function public.admin_adjust_bones(
  p_player_id uuid, p_amount bigint, p_reason text
) returns bigint language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); reason text; new_balance bigint;
begin
  perform private.assert_admin(uid); reason:=private.require_admin_reason(p_reason);
  if p_amount=0 or abs(p_amount)>1000000000 then raise exception 'INVALID_BONE_ADJUSTMENT' using errcode='22023'; end if;
  select coalesce(p.bone_count,0) into new_balance from public.profiles p
  where p.id=p_player_id and p.deleted_at is null for update;
  if not found then raise exception 'PLAYER_NOT_FOUND' using errcode='P0001'; end if;
  if new_balance+p_amount<0 then raise exception 'BALANCE_CANNOT_BE_NEGATIVE' using errcode='P0001'; end if;
  update public.profiles p set bone_count=coalesce(p.bone_count,0)+p_amount,updated_at=now()
  where p.id=p_player_id returning p.bone_count into new_balance;
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason)
  values(p_player_id,p_amount,new_balance,'admin_adjustment: '||reason);
  insert into public.admin_audit_log(admin_id,action,target_player_id,reason,details)
  values(uid,'adjust_bones',p_player_id,reason,jsonb_build_object('amount',p_amount,'balance_after',new_balance));
  return new_balance;
end $$;

revoke execute on function public.admin_search_players(text) from public,anon;
revoke execute on function public.admin_adjust_bones(uuid,bigint,text) from public,anon;
grant execute on function public.admin_search_players(text) to authenticated;
grant execute on function public.admin_adjust_bones(uuid,bigint,text) to authenticated;

-- Idempotently ensure the tables that drive live balances/map state are in
-- Supabase Realtime. The Android client also has a 5-second fallback refresh.
do $$
begin
  begin alter publication supabase_realtime add table public.profiles;
  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.world_bones;
  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.dirt_piles;
  exception when duplicate_object then null; end;
end $$;
