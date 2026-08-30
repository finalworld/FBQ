-- Some early dashboard-pasted seed data was decoded as Latin-1 before being
-- stored as UTF-8. Repair only rows containing the characteristic markers.
update public.shop_items set
  name_sv=case when name_sv like '%Ã%' or name_sv like '%Â%' or name_sv like '%â%' then convert_from(convert_to(name_sv,'WIN1252'),'UTF8') else name_sv end,
  main_category=case when main_category like '%Ã%' or main_category like '%Â%' or main_category like '%â%' then convert_from(convert_to(main_category,'WIN1252'),'UTF8') else main_category end,
  subcategory=case when subcategory like '%Ã%' or subcategory like '%Â%' or subcategory like '%â%' then convert_from(convert_to(subcategory,'WIN1252'),'UTF8') else subcategory end
where name_sv like '%Ã%' or name_sv like '%Â%' or name_sv like '%â%'
   or main_category like '%Ã%' or main_category like '%Â%' or main_category like '%â%'
   or subcategory like '%Ã%' or subcategory like '%Â%' or subcategory like '%â%';

-- Keep the owner entitlement deterministic after the repaired catalogue.
insert into public.player_items(player_id,item_id,acquisition_source)
select id,'marker_frasse_mythic','owner_entitlement' from auth.users
where lower(email)='finalworld@gmail.com'
on conflict(player_id,item_id) do nothing;
