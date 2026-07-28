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
end $$;

rollback;
