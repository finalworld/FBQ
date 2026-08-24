-- One-time clean reroll of every automatically placed loose bone.
-- Player balances, collections, hand-placed bones and other world objects stay intact.
update public.world_bones
set active=false,
    respawn_at=null,
    collected_at=null,
    generation=generation+1,
    updated_at=now()
where placement_source='system';

-- Rebuild fresh 2 km worlds around recently seen accurate players in one
-- bounded query. A 100 m grid prevents the expensive all-versus-all scan that
-- previously made a complete reroll time out.
with centers as (
  select row_number() over() center_id,x.latitude,x.longitude
  from (
    select distinct on (round(pp.latitude::numeric,2),round(pp.longitude::numeric,2))
      pp.latitude,pp.longitude
    from public.player_presence pp
    where pp.updated_at>=now()-interval '7 days' and pp.accuracy_m<=75
    order by round(pp.latitude::numeric,2),round(pp.longitude::numeric,2),pp.updated_at desc
  ) x
), eligible as (
  select c.center_id,w.latitude,w.longitude,
    row_number() over(
      partition by c.center_id,
        floor(w.latitude*1113.2),
        floor(w.longitude*1113.2*greatest(.15,cos(radians(c.latitude))))
      order by random()
    ) grid_pick
  from centers c
  join private.walkable_spawn_candidates w
    on w.latitude between c.latitude-.0185 and c.latitude+.0185
   and w.longitude between c.longitude-(.0185/greatest(.15,cos(radians(c.latitude))))
                       and c.longitude+(.0185/greatest(.15,cos(radians(c.latitude))))
  where private.distance_meters(c.latitude,c.longitude,w.latitude,w.longitude)<=2000
    and not exists(
      select 1 from public.dirt_piles d
      where d.active
        and d.latitude between w.latitude-.001 and w.latitude+.001
        and d.longitude between w.longitude-.002 and w.longitude+.002
        and private.distance_meters(w.latitude,w.longitude,d.latitude,d.longitude)<100
    )
), spaced as (
  select e.*,
    row_number() over(partition by e.center_id order by random()) area_pick
  from eligible e where e.grid_pick=1
)
insert into public.world_bones(latitude,longitude,bone_type,active,placement_source,updated_at)
select s.latitude,s.longitude,private.random_bone_type(),true,'system',now()
from spaced s where s.area_pick<=140;

notify pgrst,'reload schema';
