-- FBQ 0.400: flocks, applications, roles, member stats and bank spending.

create or replace function private.normalize_flock_name(raw_name text)
returns text language sql immutable set search_path=''
as $$ select trim(regexp_replace(coalesce(raw_name,''),'\s+',' ','g')) $$;

create or replace function private.valid_flock_name(raw_name text)
returns boolean language sql immutable set search_path=''
as $$
  select char_length(private.normalize_flock_name(raw_name)) between 3 and 24
    and private.normalize_flock_name(raw_name) ~ '^[[:alnum:]åäöÅÄÖ ]+$'
$$;

create or replace function private.flock_role(check_flock_id uuid,check_player_id uuid)
returns text language sql stable security definer set search_path=''
as $$
  select fm.role from public.flock_members fm
  where fm.flock_id=check_flock_id and fm.player_id=check_player_id
$$;

create or replace function private.assert_flock_capacity(check_player_id uuid)
returns void language plpgsql stable security definer set search_path=''
as $$
begin
  if (select count(*) from public.flock_members fm where fm.player_id=check_player_id)>=3 then
    raise exception 'FLOCK_LIMIT_REACHED' using errcode='P0001';
  end if;
end $$;

revoke all on function private.normalize_flock_name(text) from public,anon,authenticated;
revoke all on function private.valid_flock_name(text) from public,anon,authenticated;
revoke all on function private.flock_role(uuid,uuid) from public,anon,authenticated;
revoke all on function private.assert_flock_capacity(uuid) from public,anon,authenticated;

-- Direct table SELECT would expose leader_id and bank_balance publicly.
-- All flock reads therefore use purpose-specific RPC result shapes.
revoke select on public.flocks,public.flock_members,public.flock_applications,
  public.flock_bank_ledger,public.flock_items from authenticated;

create or replace function public.list_flocks(search_text text default null)
returns table(flock_id uuid,name text,icon_id text,member_count bigint)
language sql stable security definer set search_path=''
as $$
  select f.id,f.name,f.icon_id,count(fm.player_id)
  from public.flocks f left join public.flock_members fm on fm.flock_id=f.id
  where search_text is null or f.normalized_name like
    '%'||lower(private.normalize_flock_name(search_text))||'%'
  group by f.id,f.name,f.icon_id
  order by lower(f.name),f.id limit 200
$$;

create or replace function public.create_flock(flock_name text)
returns table(flock_id uuid,name text,role text,bank_balance numeric,balance bigint)
language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); normalized text; normalized_key text; fid uuid; new_balance bigint;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid); perform private.assert_flock_capacity(uid);
  normalized:=private.normalize_flock_name(flock_name); normalized_key:=lower(normalized);
  if not private.valid_flock_name(normalized) then
    raise exception 'INVALID_FLOCK_NAME' using errcode='22023';
  end if;
  select p.bone_count into new_balance from public.profiles p where p.id=uid for update;
  if new_balance<500 then raise exception 'INSUFFICIENT_BONES' using errcode='P0001'; end if;
  if exists(select 1 from public.flocks f where f.normalized_name=normalized_key) then
    raise exception 'FLOCK_NAME_TAKEN' using errcode='23505';
  end if;
  update public.profiles set bone_count=bone_count-500,updated_at=now() where id=uid
  returning bone_count into new_balance;
  insert into public.flocks(name,normalized_name,leader_id)
  values(normalized,normalized_key,uid) returning id into fid;
  insert into public.flock_members(flock_id,player_id,role) values(fid,uid,'leader');
  insert into public.player_bone_ledger(player_id,amount,balance_after,reason,source_id)
  values(uid,-500,new_balance,'create_flock',fid);
  flock_id:=fid; name:=normalized; role:='leader'; bank_balance:=0; balance:=new_balance;
  return next;
exception when unique_violation then
  raise exception 'FLOCK_NAME_TAKEN' using errcode='23505';
end $$;

create or replace function public.apply_to_flock(p_flock_id uuid)
returns text language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); used_slots integer;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid); perform private.assert_flock_capacity(uid);
  if not exists(select 1 from public.flocks where id=p_flock_id) then
    raise exception 'FLOCK_NOT_FOUND' using errcode='P0001';
  end if;
  if private.is_flock_member(p_flock_id,uid) then
    raise exception 'ALREADY_FLOCK_MEMBER' using errcode='P0001';
  end if;
  -- Pending applications reserve a membership slot and avoid later overbooking.
  select count(*) into used_slots from public.flock_members where player_id=uid;
  used_slots:=used_slots+(select count(*) from public.flock_applications
    where player_id=uid and status='pending');
  if used_slots>=3 then raise exception 'FLOCK_APPLICATION_LIMIT' using errcode='P0001'; end if;
  insert into public.flock_applications(flock_id,player_id,status,created_at,decided_at,decided_by)
  values(p_flock_id,uid,'pending',now(),null,null)
  on conflict(flock_id,player_id) do update set
    status='pending',created_at=now(),decided_at=null,decided_by=null;
  return 'pending';
end $$;

create or replace function public.cancel_flock_application(p_flock_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  update public.flock_applications set status='cancelled',decided_at=now(),decided_by=uid
  where flock_id=p_flock_id and player_id=uid and status='pending';
  if not found then raise exception 'PENDING_APPLICATION_NOT_FOUND' using errcode='P0001'; end if;
end $$;

create or replace function public.decide_flock_application(
  p_flock_id uuid,p_applicant_id uuid,p_approve boolean
) returns text language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); application public.flock_applications%rowtype;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  if coalesce(private.flock_role(p_flock_id,uid),'') not in ('leader','guard') then
    raise exception 'FLOCK_OFFICER_REQUIRED' using errcode='42501';
  end if;
  select * into application from public.flock_applications
  where flock_id=p_flock_id and player_id=p_applicant_id for update;
  if not found or application.status<>'pending' then
    raise exception 'PENDING_APPLICATION_NOT_FOUND' using errcode='P0001';
  end if;
  if p_approve then
    perform private.assert_active_player(p_applicant_id);
    perform private.assert_flock_capacity(p_applicant_id);
    insert into public.flock_members(flock_id,player_id,role)
    values(p_flock_id,p_applicant_id,'member') on conflict do nothing;
    update public.flock_applications set status='approved',decided_at=now(),decided_by=uid
    where flock_id=p_flock_id and player_id=p_applicant_id;
    -- Other pending applications remain, but any beyond remaining slots are
    -- cancelled so approval can never push the player over three memberships.
    if (select count(*) from public.flock_members where player_id=p_applicant_id)>=3 then
      update public.flock_applications set status='cancelled',decided_at=now(),decided_by=null
      where player_id=p_applicant_id and status='pending';
    end if;
    return 'approved';
  else
    update public.flock_applications set status='denied',decided_at=now(),decided_by=uid
    where flock_id=p_flock_id and player_id=p_applicant_id;
    return 'denied';
  end if;
end $$;

create or replace function public.set_flock_guard(
  p_flock_id uuid,p_member_id uuid,p_is_guard boolean
) returns text language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); current_role text; desired text;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  if private.flock_role(p_flock_id,uid)<>'leader' then
    raise exception 'FLOCK_LEADER_REQUIRED' using errcode='42501';
  end if;
  select role into current_role from public.flock_members
  where flock_id=p_flock_id and player_id=p_member_id for update;
  if not found or current_role='leader' then raise exception 'INVALID_FLOCK_MEMBER' using errcode='P0001'; end if;
  desired:=case when p_is_guard then 'guard' else 'member' end;
  update public.flock_members set role=desired where flock_id=p_flock_id and player_id=p_member_id;
  return desired;
end $$;

create or replace function public.kick_flock_member(p_flock_id uuid,p_member_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); actor_role text; target_role text;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  actor_role:=coalesce(private.flock_role(p_flock_id,uid),'');
  target_role:=coalesce(private.flock_role(p_flock_id,p_member_id),'');
  if actor_role not in ('leader','guard') or target_role is null or target_role='leader'
     or (actor_role='guard' and target_role<>'member') then
    raise exception 'FLOCK_KICK_NOT_ALLOWED' using errcode='42501';
  end if;
  delete from public.flock_members where flock_id=p_flock_id and player_id=p_member_id;
end $$;

create or replace function public.transfer_flock_leadership(p_flock_id uuid,p_new_leader_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform 1 from public.flocks where id=p_flock_id for update;
  if private.flock_role(p_flock_id,uid)<>'leader' then
    raise exception 'FLOCK_LEADER_REQUIRED' using errcode='42501';
  end if;
  if coalesce(private.flock_role(p_flock_id,p_new_leader_id),'') not in ('member','guard') then
    raise exception 'NEW_LEADER_MUST_BE_MEMBER' using errcode='P0001';
  end if;
  update public.flock_members set role='member' where flock_id=p_flock_id and player_id=uid;
  update public.flock_members set role='leader' where flock_id=p_flock_id and player_id=p_new_leader_id;
  update public.flocks set leader_id=p_new_leader_id,updated_at=now() where id=p_flock_id;
end $$;

create or replace function public.leave_flock(p_flock_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); role text;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  role:=private.flock_role(p_flock_id,uid);
  if role is null then raise exception 'NOT_FLOCK_MEMBER' using errcode='P0001'; end if;
  if role='leader' then raise exception 'TRANSFER_LEADERSHIP_FIRST' using errcode='P0001'; end if;
  delete from public.flock_members where flock_id=p_flock_id and player_id=uid;
end $$;

create or replace function public.rename_flock(p_flock_id uuid,p_new_name text)
returns table(name text,bank_balance numeric,next_rename_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); normalized text; normalized_key text; f public.flocks%rowtype;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  normalized:=private.normalize_flock_name(p_new_name); normalized_key:=lower(normalized);
  if not private.valid_flock_name(normalized) then raise exception 'INVALID_FLOCK_NAME' using errcode='22023'; end if;
  select * into f from public.flocks where id=p_flock_id for update;
  if not found then raise exception 'FLOCK_NOT_FOUND' using errcode='P0001'; end if;
  if f.leader_id<>uid then raise exception 'FLOCK_LEADER_REQUIRED' using errcode='42501'; end if;
  if f.renamed_at is not null and f.renamed_at+interval '7 days'>now() then
    raise exception 'FLOCK_RENAME_COOLDOWN' using errcode='P0001',detail=(f.renamed_at+interval '7 days')::text;
  end if;
  if f.bank_balance<500 then raise exception 'FLOCK_BANK_INSUFFICIENT' using errcode='P0001'; end if;
  update public.flocks set name=normalized,normalized_name=normalized_key,
    bank_balance=flocks.bank_balance-500,renamed_at=now(),updated_at=now()
  where id=p_flock_id returning flocks.bank_balance into bank_balance;
  insert into public.flock_bank_ledger(flock_id,actor_id,amount,balance_after,reason)
  values(p_flock_id,uid,-500,bank_balance,'rename_flock');
  name:=normalized; next_rename_at:=now()+interval '7 days'; return next;
exception when unique_violation then raise exception 'FLOCK_NAME_TAKEN' using errcode='23505';
end $$;

create or replace function public.delete_empty_flock(p_flock_id uuid,p_confirmation_name text)
returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); f public.flocks%rowtype;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  select * into f from public.flocks where id=p_flock_id for update;
  if not found then raise exception 'FLOCK_NOT_FOUND' using errcode='P0001'; end if;
  if f.leader_id<>uid then raise exception 'FLOCK_LEADER_REQUIRED' using errcode='42501'; end if;
  if private.normalize_flock_name(p_confirmation_name)<>f.name then
    raise exception 'FLOCK_DELETE_CONFIRMATION_MISMATCH' using errcode='P0001';
  end if;
  if (select count(*) from public.flock_members where flock_id=p_flock_id)<>1 then
    raise exception 'FLOCK_NOT_EMPTY' using errcode='P0001';
  end if;
  delete from public.flocks where id=p_flock_id;
end $$;

create or replace function public.get_my_flocks()
returns table(
  flock_id uuid,name text,icon_id text,my_role text,member_count bigint,
  bank_balance numeric,renamed_at timestamptz,created_at timestamptz
) language sql stable security definer set search_path=''
as $$
  select f.id,f.name,f.icon_id,mine.role,count(all_members.player_id),
    f.bank_balance,f.renamed_at,f.created_at
  from public.flock_members mine join public.flocks f on f.id=mine.flock_id
  join public.flock_members all_members on all_members.flock_id=f.id
  where mine.player_id=auth.uid()
  group by f.id,f.name,f.icon_id,mine.role,f.bank_balance,f.renamed_at,f.created_at
  order by f.created_at
$$;

create or replace function public.get_flock_members(p_flock_id uuid)
returns table(
  player_id uuid,display_name text,role text,joined_at timestamptz,
  bone_balance bigint,total_meters bigint,total_bones bigint,total_piles bigint,
  collection jsonb
) language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  if not private.is_flock_member(p_flock_id,auth.uid()) then
    raise exception 'FLOCK_MEMBER_REQUIRED' using errcode='42501';
  end if;
  return query
  select p.id,p.display_name,fm.role,fm.joined_at,p.bone_count,p.total_meters,p.total_bones,p.total_piles,
    coalesce((select jsonb_agg(jsonb_build_object('bone_type',c.bone_type,'count',c.lifetime_count)
      order by c.bone_type) from public.player_bone_collection c where c.player_id=p.id),'[]'::jsonb)
  from public.flock_members fm join public.profiles p on p.id=fm.player_id
  where fm.flock_id=p_flock_id and p.deleted_at is null
  order by case fm.role when 'leader' then 0 when 'guard' then 1 else 2 end,lower(p.display_name),p.id;
end $$;

create or replace function public.get_flock_applications(p_flock_id uuid)
returns table(player_id uuid,display_name text,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
  if coalesce(private.flock_role(p_flock_id,auth.uid()),'') not in ('leader','guard') then
    raise exception 'FLOCK_OFFICER_REQUIRED' using errcode='42501';
  end if;
  return query select a.player_id,p.display_name,a.created_at
    from public.flock_applications a join public.profiles p on p.id=a.player_id
    where a.flock_id=p_flock_id and a.status='pending' order by a.created_at;
end $$;

create or replace function public.get_flock_ledger(p_flock_id uuid,p_limit integer default 100)
returns table(
  entry_id bigint,actor_name text,amount numeric,balance_after numeric,
  reason text,created_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
begin
  if not private.is_flock_member(p_flock_id,auth.uid()) then
    raise exception 'FLOCK_MEMBER_REQUIRED' using errcode='42501';
  end if;
  return query select l.id,coalesce(p.display_name,'Borttagen spelare'),l.amount,l.balance_after,l.reason,l.created_at
    from public.flock_bank_ledger l left join public.profiles p on p.id=l.actor_id
    where l.flock_id=p_flock_id order by l.created_at desc,l.id desc
    limit least(greatest(coalesce(p_limit,100),1),500);
end $$;

-- No API routine is executable by anonymous users.
revoke execute on function public.list_flocks(text) from public,anon;
revoke execute on function public.create_flock(text) from public,anon;
revoke execute on function public.apply_to_flock(uuid) from public,anon;
revoke execute on function public.cancel_flock_application(uuid) from public,anon;
revoke execute on function public.decide_flock_application(uuid,uuid,boolean) from public,anon;
revoke execute on function public.set_flock_guard(uuid,uuid,boolean) from public,anon;
revoke execute on function public.kick_flock_member(uuid,uuid) from public,anon;
revoke execute on function public.transfer_flock_leadership(uuid,uuid) from public,anon;
revoke execute on function public.leave_flock(uuid) from public,anon;
revoke execute on function public.rename_flock(uuid,text) from public,anon;
revoke execute on function public.delete_empty_flock(uuid,text) from public,anon;
revoke execute on function public.get_my_flocks() from public,anon;
revoke execute on function public.get_flock_members(uuid) from public,anon;
revoke execute on function public.get_flock_applications(uuid) from public,anon;
revoke execute on function public.get_flock_ledger(uuid,integer) from public,anon;

grant execute on function public.list_flocks(text) to authenticated;
grant execute on function public.create_flock(text) to authenticated;
grant execute on function public.apply_to_flock(uuid) to authenticated;
grant execute on function public.cancel_flock_application(uuid) to authenticated;
grant execute on function public.decide_flock_application(uuid,uuid,boolean) to authenticated;
grant execute on function public.set_flock_guard(uuid,uuid,boolean) to authenticated;
grant execute on function public.kick_flock_member(uuid,uuid) to authenticated;
grant execute on function public.transfer_flock_leadership(uuid,uuid) to authenticated;
grant execute on function public.leave_flock(uuid) to authenticated;
grant execute on function public.rename_flock(uuid,text) to authenticated;
grant execute on function public.delete_empty_flock(uuid,text) to authenticated;
grant execute on function public.get_my_flocks() to authenticated;
grant execute on function public.get_flock_members(uuid) to authenticated;
grant execute on function public.get_flock_applications(uuid) to authenticated;
grant execute on function public.get_flock_ledger(uuid,integer) to authenticated;
