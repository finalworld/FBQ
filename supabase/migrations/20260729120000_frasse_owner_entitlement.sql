-- One-time owner entitlement. The email is resolved server-side to the
-- immutable auth UUID; the Android client never contains an owner shortcut.
insert into public.player_entitlements(player_id,item_id,reason)
select id,'marker_frasse_mythic','Frasses owner launch entitlement'
from auth.users where lower(email)='finalworld@gmail.com'
on conflict(player_id,item_id) do nothing;

insert into public.player_items(player_id,item_id,acquisition_source)
select id,'marker_frasse_mythic','owner_entitlement'
from auth.users where lower(email)='finalworld@gmail.com'
on conflict(player_id,item_id) do nothing;
