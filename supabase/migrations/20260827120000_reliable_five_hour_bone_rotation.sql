-- Rotate automatic bones independently of GPS presence. The latency fast path
-- intentionally stopped doing world maintenance inside update_presence; without
-- a scheduler, five-hour-old bones could therefore remain on "soon" forever.

create or replace function private.rotate_expired_world_bones()
returns integer language plpgsql volatile security definer set search_path='' as $$
declare rotated integer;
begin
  if not pg_try_advisory_xact_lock(1179666258) then return 0; end if;

  -- A generation is the logical map item. Renewing it atomically makes the old
  -- bone disappear and a newly rolled bone appear without any GPS transaction.
  with stale as (
    select b.id
    from public.world_bones b
    where b.active
      and b.placement_source='system'
      and b.updated_at<=now()-interval '5 hours'
    order by b.updated_at
    limit 500
    for update skip locked
  ), renewed as (
    update public.world_bones b
    set bone_type=private.random_bone_type(),active=true,respawn_at=null,
        collected_at=null,generation=b.generation+1,updated_at=now()
    from stale where b.id=stale.id
    returning 1
  )
  select count(*) into rotated from renewed;
  return rotated;
end $$;

revoke all on function private.rotate_expired_world_bones() from public,anon,authenticated;

create extension if not exists pg_cron;

do $$
declare existing_job bigint;
begin
  select jobid into existing_job from cron.job
  where jobname='fbq-rotate-five-hour-bones'
  order by jobid desc limit 1;
  if existing_job is not null then perform cron.unschedule(existing_job); end if;
  perform cron.schedule('fbq-rotate-five-hour-bones','* * * * *',
    'select private.rotate_expired_world_bones()');
end $$;

-- Repair up to 500 already overdue bones now. The minute job drains any rest.
select private.rotate_expired_world_bones();

notify pgrst,'reload schema';
