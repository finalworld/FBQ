create or replace function public.get_poi_settings()
returns table(show_dog_parks boolean,show_pet_shops boolean,show_vets boolean,show_grooming boolean)
language plpgsql volatile security definer set search_path='' as $$
begin
 insert into public.player_settings(player_id) values(auth.uid()) on conflict(player_id) do nothing;
 return query select s.show_dog_parks,s.show_pet_shops,s.show_vets,s.show_grooming from public.player_settings s where s.player_id=auth.uid();
end $$;
create or replace function public.update_poi_settings(p_show_dog_parks boolean,p_show_pet_shops boolean,p_show_vets boolean,p_show_grooming boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 insert into public.player_settings(player_id,show_dog_parks,show_pet_shops,show_vets,show_grooming,updated_at)
 values(auth.uid(),p_show_dog_parks,p_show_pet_shops,p_show_vets,p_show_grooming,now())
 on conflict(player_id) do update set show_dog_parks=excluded.show_dog_parks,show_pet_shops=excluded.show_pet_shops,show_vets=excluded.show_vets,show_grooming=excluded.show_grooming,updated_at=now();
end $$;
revoke execute on function public.get_poi_settings() from public,anon;
revoke execute on function public.update_poi_settings(boolean,boolean,boolean,boolean) from public,anon;
grant execute on function public.get_poi_settings() to authenticated;
grant execute on function public.update_poi_settings(boolean,boolean,boolean,boolean) to authenticated;
