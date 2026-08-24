-- A nearby player's GPS heartbeat may briefly lag even while both phones are
-- together. Keep the collector strict (the app writes a live fix first), but
-- allow recent nearby companions to share the reward reliably.
do $$ declare d text;begin
  d:=pg_get_functiondef('public.collect_nearby_bones()'::regprocedure);
  d:=replace(d,'interval ''45 seconds''','interval ''2 minutes''');
  d:=replace(d,'greatest(25, least(','greatest(40, least(');
  d:=replace(d,'greatest(25,least(','greatest(40,least(');
  execute d;
end $$;

-- Dog poop stays hidden for ten minutes after it is dropped.
alter table public.world_dog_poops
  alter column visible_at set default (now()+interval '10 minutes');
update public.world_dog_poops
set visible_at=created_at+interval '10 minutes'
where active;

drop policy if exists visible_poops_read on public.world_dog_poops;
create policy visible_poops_read on public.world_dog_poops for select to authenticated
  using(active and visible_at<=now() and expires_at>now());

notify pgrst,'reload schema';
