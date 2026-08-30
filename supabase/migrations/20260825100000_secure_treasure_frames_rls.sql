-- Security advisor: treasure_frames is a public read-only catalogue, but every
-- exposed public table must still use RLS.
alter table public.treasure_frames enable row level security;

drop policy if exists treasure_frames_authenticated_read on public.treasure_frames;
create policy treasure_frames_authenticated_read
  on public.treasure_frames for select to authenticated
  using(true);

revoke all on public.treasure_frames from anon;
revoke insert,update,delete,truncate,references,trigger
  on public.treasure_frames from authenticated;
grant select on public.treasure_frames to authenticated;

notify pgrst,'reload schema';
