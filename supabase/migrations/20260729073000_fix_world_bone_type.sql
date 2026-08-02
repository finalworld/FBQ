-- Legacy world_bones used integer while the 0.400 economy catalog and ledger
-- use smallint. Normalize it so collection inserts are type-safe.
alter table public.world_bones
  alter column bone_type type smallint using bone_type::smallint;
