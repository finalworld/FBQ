-- Reject stale or forged member identifiers instead of reporting a no-op kick.
create or replace function public.kick_flock_member(p_flock_id uuid,p_member_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); actor_role text; target_role text;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  actor_role:=coalesce(private.flock_role(p_flock_id,uid),'');
  target_role:=coalesce(private.flock_role(p_flock_id,p_member_id),'');
  if actor_role not in ('leader','guard') or target_role=''
     or target_role='leader' or (actor_role='guard' and target_role<>'member') then
    raise exception 'FLOCK_KICK_NOT_ALLOWED' using errcode='42501';
  end if;
  delete from public.flock_members
  where flock_id=p_flock_id and player_id=p_member_id;
  if not found then raise exception 'FLOCK_MEMBER_NOT_FOUND' using errcode='P0001'; end if;
end $$;

revoke execute on function public.kick_flock_member(uuid,uuid) from public,anon;
grant execute on function public.kick_flock_member(uuid,uuid) to authenticated;
