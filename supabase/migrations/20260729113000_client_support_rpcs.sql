create or replace function public.get_bone_collection()
returns table(bone_type integer,lifetime_count bigint,first_discovered_at timestamptz)
language sql stable security definer set search_path=''
as $$
  select bt.id,coalesce(c.lifetime_count,0),c.first_discovered_at
  from public.bone_types bt left join public.player_bone_collection c
    on c.bone_type=bt.id and c.player_id=auth.uid()
  order by bt.id
$$;

create or replace function public.update_game_settings(
  p_walking_mode_enabled boolean,p_bark_enabled boolean,p_vibration_enabled boolean
) returns void language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(auth.uid());
  update public.profiles set
    walking_mode_enabled=p_walking_mode_enabled,bark_enabled=p_bark_enabled,
    vibration_enabled=p_vibration_enabled,updated_at=now()
  where id=auth.uid();
end
$$;

revoke execute on function public.get_bone_collection() from public,anon;
revoke execute on function public.update_game_settings(boolean,boolean,boolean) from public,anon;
grant execute on function public.get_bone_collection() to authenticated;
grant execute on function public.update_game_settings(boolean,boolean,boolean) to authenticated;
