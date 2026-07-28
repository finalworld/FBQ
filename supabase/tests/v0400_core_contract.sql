-- Read-only regression checks for the FBQ 0.400 database contract.
-- Run after all migrations. Any failed assertion aborts the transaction.
begin;

do $$
declare total_weight integer; total_types integer;
begin
  select sum(spawn_weight),count(*) into total_weight,total_types from public.bone_types;
  if total_weight<>10000 or total_types<>12 then
    raise exception 'Bone catalogue invalid: types %, weight %',total_types,total_weight;
  end if;
  if (select array_agg(value order by id) from public.bone_types)
     <> array[1,2,3,5,8,12,20,35,60,100,175,300] then
    raise exception 'Bone values differ from locked specification';
  end if;
  if (select array_agg(cost order by id) from public.pile_types)
     <> array[10,25,50,100,250] then
    raise exception 'Pile costs differ from locked specification';
  end if;
  if (select array_agg(double_chance_per_million order by id) from public.pile_types)
     <> array[1000,2000,4000,7000,10000] then
    raise exception 'Pile double chances differ from locked specification';
  end if;
end $$;

do $$
declare total integer;
begin
  select count(*) into total from public.shop_items where main_category='Markörer' and active;
  if total<>96 then raise exception 'Expected 96 launch markers, got %',total; end if;
  if (select count(*) from public.shop_items where subcategory='Hundraser' and active)<>36
    or (select count(*) from public.shop_items where subcategory='Hundleksaker' and active)<>20
    or (select count(*) from public.shop_items where subcategory='Tassar' and active)<>12
    or (select count(*) from public.shop_items where subcategory='Halsband och namnbrickor' and active)<>10
    or (select count(*) from public.shop_items where subcategory='Koppel och utrustning' and active)<>8
    or (select count(*) from public.shop_items where subcategory='Emblem och övrigt' and active)<>10 then
    raise exception 'Marker category totals differ from specification';
  end if;
  if (select count(*) from public.shop_items where rarity='common' and active)<>30
    or (select count(*) from public.shop_items where rarity='uncommon' and active)<>24
    or (select count(*) from public.shop_items where rarity='rare' and active)<>18
    or (select count(*) from public.shop_items where rarity='epic' and active)<>14
    or (select count(*) from public.shop_items where rarity='legendary' and active)<>8
    or (select count(*) from public.shop_items where rarity='mythic' and active)<>1 then
    raise exception 'Marker rarity totals differ from specification';
  end if;
  if not exists(select 1 from public.shop_items
    where id='marker_frasse_mythic' and price=10000 and rarity='mythic') then
    raise exception 'Mythic Frasse marker missing or incorrectly priced';
  end if;
end $$;

do $$
begin
  if has_table_privilege('authenticated','public.profiles','UPDATE') then
    raise exception 'Authenticated may directly update profiles';
  end if;
  if has_table_privilege('authenticated','public.player_presence','INSERT')
     or has_table_privilege('authenticated','public.player_presence','UPDATE') then
    raise exception 'Authenticated may bypass update_presence RPC';
  end if;
  if has_table_privilege('authenticated','public.flocks','UPDATE') then
    raise exception 'Authenticated may directly mutate flock economy';
  end if;
  if has_table_privilege('authenticated','public.flocks','SELECT') then
    raise exception 'Authenticated can bypass safe flock projections';
  end if;
  if has_function_privilege('anon','public.collect_nearby_bones()','EXECUTE') then
    raise exception 'Anonymous role can collect bones';
  end if;
  if not has_function_privilege('authenticated','public.collect_nearby_bones()','EXECUTE') then
    raise exception 'Authenticated role cannot collect bones';
  end if;
  if has_function_privilege('anon','public.open_dirt_pile(uuid)','EXECUTE')
     or has_function_privilege('anon','public.spin_home_slot(uuid,smallint)','EXECUTE') then
    raise exception 'Anonymous role can use economy RPCs';
  end if;
  if has_function_privilege('anon','public.list_flocks(text)','EXECUTE')
     or not has_function_privilege('authenticated','public.get_my_flocks()','EXECUTE') then
    raise exception 'Flock RPC privileges invalid';
  end if;
  if has_function_privilege('anon','public.buy_shop_item(uuid,text,uuid)','EXECUTE')
     or not has_function_privilege('authenticated','public.equip_marker(text)','EXECUTE') then
    raise exception 'Shop RPC privileges invalid';
  end if;
  if has_table_privilege('authenticated','public.admin_users','SELECT')
     or has_function_privilege('anon','public.admin_adjust_bones(uuid,bigint,text)','EXECUTE') then
    raise exception 'Admin boundary privileges invalid';
  end if;
  if not has_function_privilege('authenticated','public.list_map_pois(double precision,double precision,double precision,double precision)','EXECUTE') then
    raise exception 'Authenticated role cannot load map POIs';
  end if;
end $$;

rollback;
