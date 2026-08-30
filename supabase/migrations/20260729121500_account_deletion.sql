create or replace function public.delete_my_account(p_confirmation_name text)
returns void language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid();current_name text;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  select display_name into current_name from public.profiles where id=uid for update;
  if current_name is null or private.normalize_game_name(p_confirmation_name)<>current_name then
    raise exception 'ACCOUNT_DELETE_CONFIRMATION_MISMATCH' using errcode='P0001';
  end if;
  if exists(select 1 from public.flocks where leader_id=uid) then
    raise exception 'TRANSFER_FLOCK_LEADERSHIP_FIRST' using errcode='P0001';
  end if;
  update public.profiles set display_name='Borttagen spelare',normalized_name='borttagen spelare',
    deleted_at=now(),updated_at=now() where id=uid;
  delete from public.player_presence where player_id=uid;
  delete from public.flock_applications where player_id=uid;
  delete from public.flock_members where player_id=uid;
  -- Keep the auth row as a disabled identity so historical UUID references and
  -- audit trails remain valid; login is permanently blocked by deleted_at.
end $$;
revoke execute on function public.delete_my_account(text) from public,anon;
grant execute on function public.delete_my_account(text) to authenticated;
