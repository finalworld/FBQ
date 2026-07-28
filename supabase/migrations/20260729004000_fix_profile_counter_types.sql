-- Legacy 0.300 databases may already have these counters as integer.
-- The 0.400 RPC contracts expose them as bigint, so normalize the stored types.
alter table public.profiles
  alter column total_bones type bigint using total_bones::bigint,
  alter column total_piles type bigint using total_piles::bigint;
