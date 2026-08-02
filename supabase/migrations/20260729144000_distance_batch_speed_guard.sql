create or replace function public.add_distance_batch(
  client_batch_id uuid, meters integer,
  sample_started_at timestamptz, sample_ended_at timestamptz
) returns bigint language plpgsql security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid(); result bigint;
  elapsed_seconds double precision; maximum_plausible_meters integer;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
  perform private.assert_active_player(uid);
  elapsed_seconds:=extract(epoch from (sample_ended_at-sample_started_at));
  maximum_plausible_meters:=ceil(greatest(elapsed_seconds,0)*3.34+50)::integer;
  if meters<0 or meters>200000 or sample_ended_at<sample_started_at
     or sample_ended_at-sample_started_at>interval '2 hours'
     or sample_ended_at>now()+interval '5 minutes'
     or sample_started_at<now()-interval '3 hours'
     or meters>maximum_plausible_meters then
    raise exception 'INVALID_DISTANCE_BATCH' using errcode='22023';
  end if;
  insert into public.distance_batches(player_id,client_batch_id,meters,sample_started_at,sample_ended_at)
  values(uid,client_batch_id,meters,sample_started_at,sample_ended_at)
  on conflict(player_id,client_batch_id) do nothing;
  if found then update public.profiles set total_meters=total_meters+meters,updated_at=now() where id=uid; end if;
  select total_meters into result from public.profiles where id=uid;
  return result;
end $$;
revoke execute on function public.add_distance_batch(uuid,integer,timestamptz,timestamptz) from public,anon;
grant execute on function public.add_distance_batch(uuid,integer,timestamptz,timestamptz) to authenticated;
