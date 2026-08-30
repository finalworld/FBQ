create or replace function public.get_my_bone_balance()
returns bigint
language sql
stable
security definer
set search_path=''
as $$
  select p.bone_count
  from public.profiles p
  where p.id=auth.uid()
$$;

revoke execute on function public.get_my_bone_balance() from public,anon;
grant execute on function public.get_my_bone_balance() to authenticated;
