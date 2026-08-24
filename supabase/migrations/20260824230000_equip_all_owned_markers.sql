-- Treasure rewards use stable hunt_* ids rather than marker_* ids. Ownership
-- and the catalogue category are the authority, not an id naming convention.
create or replace function public.equip_marker(p_item_id text)
returns text language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  perform private.assert_active_player(uid);
  if not exists(
    select 1 from public.player_items pi
    join public.shop_items i on i.id=pi.item_id
    where pi.player_id=uid and pi.item_id=p_item_id and i.active
      and i.main_category='Markörer'
  ) then raise exception 'MARKER_NOT_OWNED' using errcode='42501';end if;
  update public.profiles set active_marker_id=p_item_id,updated_at=now() where id=uid;
  return p_item_id;
end $$;
revoke execute on function public.equip_marker(text) from public,anon;
grant execute on function public.equip_marker(text) to authenticated;
notify pgrst,'reload schema';
