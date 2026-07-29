create or replace function public.get_flock_member_bone_collection(
  p_flock_id uuid,p_member_id uuid
) returns table(bone_type smallint,lifetime_count bigint)
language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  if not private.is_flock_member(p_flock_id,auth.uid())
     or not private.is_flock_member(p_flock_id,p_member_id) then
    raise exception 'FLOCK_MEMBER_REQUIRED' using errcode='42501';
  end if;
  return query select t.id,coalesce(l.lifetime_count,0)
  from public.bone_types t left join public.player_bone_lifetime l
    on l.bone_type=t.id and l.player_id=p_member_id order by t.id;
end $$;
revoke execute on function public.get_flock_member_bone_collection(uuid,uuid) from public,anon;
grant execute on function public.get_flock_member_bone_collection(uuid,uuid) to authenticated;
