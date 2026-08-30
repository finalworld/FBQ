-- Frasse toys are a permanent player currency, not scoped to one event run.
create table if not exists public.player_toy_wallets(
  player_id uuid primary key references auth.users(id) on delete cascade,
  balance integer not null default 0 check(balance>=0),
  lifetime_collected bigint not null default 0 check(lifetime_collected>=0),
  updated_at timestamptz not null default now()
);
alter table public.player_toy_wallets enable row level security;
revoke all on public.player_toy_wallets from anon,authenticated;

insert into public.player_toy_wallets(player_id,balance,lifetime_collected)
select player_id,sum(balance)::integer,sum(lifetime_collected) from public.event_wallets group by player_id
on conflict(player_id) do nothing;

create or replace function public.get_frasse_escape_event(p_latitude double precision default null,p_longitude double precision default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();ev public.game_events%rowtype;day date:=private.fbq_event_day();bal integer:=0;seen boolean:=false;result jsonb;
begin
  if uid is null then raise exception 'AUTH_REQUIRED';end if;
  update public.game_events set active=false where active and ends_at<=now();
  select * into ev from public.game_events where event_type='frasse_escape' and active and starts_at<=now() and ends_at>now() order by starts_at desc limit 1;
  select coalesce(w.balance,0) into bal from public.player_toy_wallets w where w.player_id=uid;
  if not found then bal:=0;end if;
  if ev.id is null then return jsonb_build_object('active',false,'toys','[]'::jsonb,'glows','[]'::jsonb,'toy_balance',bal,'show_intro',false);end if;
  if p_latitude between -90 and 90 and p_longitude between -180 and 180 then perform private.ensure_frasse_toys(ev.id,day,p_latitude,p_longitude);end if;
  select exists(select 1 from public.event_intro_seen s where s.event_id=ev.id and s.event_day=day and s.player_id=uid) into seen;
  select jsonb_build_object('active',true,'event_id',ev.id,'title',ev.title,'story',ev.story,'ends_at',ev.ends_at,'event_day',day,
    'show_intro',not seen,'toy_balance',bal,'equipped_glow',p.active_glow_color,
    'toys',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'toy_type',t.toy_type,'latitude',t.latitude,'longitude',t.longitude))
      from public.event_toys t where t.event_id=ev.id and t.event_day=day and p_latitude is not null and p_longitude is not null
      and private.distance_meters(p_latitude,p_longitude,t.latitude,t.longitude)<=2000
      and not exists(select 1 from public.event_toy_collections c where c.toy_id=t.id and c.player_id=uid)),'[]'::jsonb),
    'glows',coalesce((select jsonb_agg(jsonb_build_object('color_id',g.color_id,
      'owned',exists(select 1 from public.player_marker_glows o where o.player_id=uid and o.color_id=g.color_id),
      'equipped',coalesce(p.active_glow_color=g.color_id,false)))
      from (values('gold'),('red'),('pink'),('purple'),('blue'),('cyan'),('green'),('lime'),('orange'),('white'))g(color_id)),'[]'::jsonb)) into result
  from public.profiles p where p.id=uid;
  return result;
end $$;

create or replace function public.claim_event_toy(p_toy_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();ev public.game_events%rowtype;t public.event_toys%rowtype;me public.player_presence%rowtype;bal integer;
begin
  if uid is null then raise exception 'AUTH_REQUIRED';end if;
  select * into ev from public.game_events where event_type='frasse_escape' and active and now()<ends_at order by starts_at desc limit 1;
  if not found then raise exception 'EVENT_NOT_ACTIVE';end if;
  select * into t from public.event_toys where id=p_toy_id and event_id=ev.id and event_day=private.fbq_event_day();if not found then raise exception 'TOY_GONE';end if;
  select * into me from public.player_presence where player_id=uid;if not found or me.updated_at<now()-interval '60 seconds' or me.accuracy_m>75 then raise exception 'ACCURATE_LOCATION_REQUIRED';end if;
  if private.distance_meters(me.latitude,me.longitude,t.latitude,t.longitude)>greatest(30,least(me.accuracy_m,60)) then raise exception 'TOY_OUT_OF_RANGE';end if;
  insert into public.event_toy_collections(toy_id,player_id) values(t.id,uid) on conflict do nothing;if not found then raise exception 'TOY_ALREADY_COLLECTED';end if;
  insert into public.player_toy_wallets(player_id,balance,lifetime_collected) values(uid,1,1)
  on conflict(player_id) do update set balance=public.player_toy_wallets.balance+1,lifetime_collected=public.player_toy_wallets.lifetime_collected+1,updated_at=now() returning balance into bal;
  insert into public.player_event_log(player_id,category,title,details) values(uid,'other','Hittade en av Frasses leksaker',jsonb_build_object('toy_type',t.toy_type,'event_id',ev.id));
  return jsonb_build_object('toy_id',t.id,'toy_type',t.toy_type,'toy_balance',bal);
end $$;

create or replace function public.buy_event_glow(p_color_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();ev uuid;bal integer;begin
  if p_color_id not in('gold','red','pink','purple','blue','cyan','green','lime','orange','white') then raise exception 'INVALID_GLOW';end if;
  select id into ev from public.game_events where event_type='frasse_escape' and active and now()<ends_at order by starts_at desc limit 1;if ev is null then raise exception 'EVENT_NOT_ACTIVE';end if;
  if exists(select 1 from public.player_marker_glows where player_id=uid and color_id=p_color_id) then
    update public.profiles set active_glow_color=p_color_id where id=uid;select balance into bal from public.player_toy_wallets where player_id=uid;
    return jsonb_build_object('toy_balance',coalesce(bal,0),'equipped_glow',p_color_id,'already_owned',true);
  end if;
  update public.player_toy_wallets set balance=balance-100,updated_at=now() where player_id=uid and balance>=100 returning balance into bal;if not found then raise exception 'NOT_ENOUGH_TOYS';end if;
  insert into public.player_marker_glows(player_id,color_id) values(uid,p_color_id);update public.profiles set active_glow_color=p_color_id where id=uid;
  return jsonb_build_object('toy_balance',bal,'equipped_glow',p_color_id,'already_owned',false);
end $$;

revoke execute on function public.get_frasse_escape_event(double precision,double precision),public.claim_event_toy(uuid),public.buy_event_glow(text) from public,anon;
grant execute on function public.get_frasse_escape_event(double precision,double precision),public.claim_event_toy(uuid),public.buy_event_glow(text) to authenticated;
notify pgrst,'reload schema';
