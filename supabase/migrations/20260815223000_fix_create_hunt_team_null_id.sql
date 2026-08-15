create or replace function public.create_hunt_team() returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid:=auth.uid();
  tid uuid;
begin
  if uid is null then raise exception 'AUTH_REQUIRED';end if;

  select team_id into tid
  from public.hunt_team_members
  where player_id=uid;

  if tid is not null then return tid;end if;

  tid:=gen_random_uuid();
  insert into public.hunt_teams(id,leader_id) values(tid,uid);
  insert into public.hunt_team_members(team_id,player_id) values(tid,uid);
  return tid;
end
$$;

grant execute on function public.create_hunt_team() to authenticated;
