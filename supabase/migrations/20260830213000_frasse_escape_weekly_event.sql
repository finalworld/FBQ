-- First admin-controlled FBQ weekly event: Frasse has escaped with his toys.
create table if not exists public.game_events(
  id uuid primary key default gen_random_uuid(),event_type text not null,
  title text not null,story text not null,active boolean not null default true,
  starts_at timestamptz not null default now(),ends_at timestamptz not null,
  activated_by uuid references auth.users(id),created_at timestamptz not null default now()
);
create unique index if not exists one_active_event_type on public.game_events(event_type) where active;

create table if not exists public.event_toys(
  id uuid primary key default gen_random_uuid(),event_id uuid not null references public.game_events(id) on delete cascade,
  event_day date not null,toy_type smallint not null check(toy_type between 0 and 19),
  latitude double precision not null,longitude double precision not null,created_at timestamptz not null default now()
);
create index if not exists event_toys_day_location on public.event_toys(event_id,event_day,latitude,longitude);
create table if not exists public.event_toy_collections(
  toy_id uuid not null references public.event_toys(id) on delete cascade,player_id uuid not null references auth.users(id) on delete cascade,
  collected_at timestamptz not null default now(),primary key(toy_id,player_id)
);
create table if not exists public.event_wallets(
  event_id uuid not null references public.game_events(id) on delete cascade,player_id uuid not null references auth.users(id) on delete cascade,
  balance integer not null default 0 check(balance>=0),lifetime_collected integer not null default 0,
  updated_at timestamptz not null default now(),primary key(event_id,player_id)
);
create table if not exists public.player_marker_glows(
  player_id uuid not null references auth.users(id) on delete cascade,color_id text not null,
  purchased_at timestamptz not null default now(),primary key(player_id,color_id)
);
alter table public.profiles add column if not exists active_glow_color text;
create table if not exists public.event_intro_seen(
  event_id uuid not null references public.game_events(id) on delete cascade,event_day date not null,
  player_id uuid not null references auth.users(id) on delete cascade,seen_at timestamptz not null default now(),
  primary key(event_id,event_day,player_id)
);

alter table public.game_events enable row level security;alter table public.event_toys enable row level security;
alter table public.event_toy_collections enable row level security;alter table public.event_wallets enable row level security;
alter table public.player_marker_glows enable row level security;alter table public.event_intro_seen enable row level security;
revoke all on public.game_events,public.event_toys,public.event_toy_collections,public.event_wallets,public.player_marker_glows,public.event_intro_seen from anon,authenticated;

create or replace function private.fbq_event_day() returns date language sql stable set search_path='' as $$
  select ((now() at time zone 'Europe/Stockholm')-interval '7 hours')::date
$$;

create or replace function private.ensure_frasse_toys(p_event_id uuid,p_day date,p_lat double precision,p_lon double precision)
returns void language plpgsql volatile security definer set search_path='' as $$
declare n integer;needed integer;
begin
  if not pg_try_advisory_xact_lock(hashtext(p_event_id::text||p_day::text||round(p_lat::numeric,2)::text||round(p_lon::numeric,2)::text)) then return;end if;
  select count(*) into n from public.event_toys t where t.event_id=p_event_id and t.event_day=p_day
    and t.latitude between p_lat-.0185 and p_lat+.0185
    and t.longitude between p_lon-(.0185/greatest(.15,cos(radians(p_lat)))) and p_lon+(.0185/greatest(.15,cos(radians(p_lat))))
    and private.distance_meters(p_lat,p_lon,t.latitude,t.longitude)<=2000;
  needed:=greatest(0,650-n);if needed=0 then return;end if;
  insert into public.event_toys(event_id,event_day,toy_type,latitude,longitude)
  select p_event_id,p_day,floor(random()*20)::smallint,q.latitude,q.longitude from(
    select c.latitude,c.longitude,row_number() over(partition by floor(c.latitude*2226.4),floor(c.longitude*2226.4*greatest(.15,cos(radians(p_lat)))) order by random()) cell_pick
    from private.walkable_spawn_candidates c
    where c.latitude between p_lat-.0185 and p_lat+.0185
      and c.longitude between p_lon-(.0185/greatest(.15,cos(radians(p_lat)))) and p_lon+(.0185/greatest(.15,cos(radians(p_lat))))
      and private.distance_meters(p_lat,p_lon,c.latitude,c.longitude)<=2000
      and not exists(select 1 from public.event_toys t where t.event_id=p_event_id and t.event_day=p_day
        and t.latitude between c.latitude-.0005 and c.latitude+.0005 and t.longitude between c.longitude-.001 and c.longitude+.001
        and private.distance_meters(c.latitude,c.longitude,t.latitude,t.longitude)<50)
  )q where q.cell_pick=1 order by random() limit needed;
  delete from public.event_toys where event_id=p_event_id and event_day<p_day-1;
end $$;
revoke all on function private.fbq_event_day(),private.ensure_frasse_toys(uuid,date,double precision,double precision) from public,anon,authenticated;

create or replace function public.get_frasse_escape_event(p_latitude double precision default null,p_longitude double precision default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();ev public.game_events%rowtype;day date:=private.fbq_event_day();bal integer:=0;seen boolean:=false;result jsonb;
begin
  if uid is null then raise exception 'AUTH_REQUIRED';end if;
  update public.game_events set active=false where active and ends_at<=now();
  select * into ev from public.game_events where event_type='frasse_escape' and active and starts_at<=now() and ends_at>now() order by starts_at desc limit 1;
  if not found then return jsonb_build_object('active',false,'toys','[]'::jsonb,'glows','[]'::jsonb,'toy_balance',0,'show_intro',false);end if;
  if p_latitude between -90 and 90 and p_longitude between -180 and 180 then perform private.ensure_frasse_toys(ev.id,day,p_latitude,p_longitude);end if;
  select coalesce(w.balance,0) into bal from public.event_wallets w where w.event_id=ev.id and w.player_id=uid;
  select exists(select 1 from public.event_intro_seen s where s.event_id=ev.id and s.event_day=day and s.player_id=uid) into seen;
  select jsonb_build_object('active',true,'event_id',ev.id,'title',ev.title,'story',ev.story,'ends_at',ev.ends_at,'event_day',day,
    'show_intro',not seen,'toy_balance',coalesce(bal,0),'equipped_glow',p.active_glow_color,
    'toys',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'toy_type',t.toy_type,'latitude',t.latitude,'longitude',t.longitude))
      from public.event_toys t where t.event_id=ev.id and t.event_day=day
      and (p_latitude is null or private.distance_meters(p_latitude,p_longitude,t.latitude,t.longitude)<=2000)
      and not exists(select 1 from public.event_toy_collections c where c.toy_id=t.id and c.player_id=uid)),'[]'::jsonb),
    'glows',coalesce((select jsonb_agg(jsonb_build_object('color_id',g.color_id,'owned',exists(select 1 from public.player_marker_glows o where o.player_id=uid and o.color_id=g.color_id),'equipped',p.active_glow_color=g.color_id))
      from (values('gold'),('red'),('pink'),('purple'),('blue'),('cyan'),('green'),('lime'),('orange'),('white'))g(color_id)),'[]'::jsonb)) into result
  from public.profiles p where p.id=uid;return result;
end $$;

create or replace function public.claim_event_toy(p_toy_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();ev public.game_events%rowtype;t public.event_toys%rowtype;me public.player_presence%rowtype;bal integer;
begin
  if uid is null then raise exception 'AUTH_REQUIRED';end if;select * into ev from public.game_events where event_type='frasse_escape' and active and now()<ends_at order by starts_at desc limit 1;
  if not found then raise exception 'EVENT_NOT_ACTIVE';end if;select * into t from public.event_toys where id=p_toy_id and event_id=ev.id and event_day=private.fbq_event_day();if not found then raise exception 'TOY_GONE';end if;
  select * into me from public.player_presence where player_id=uid;if not found or me.updated_at<now()-interval '60 seconds' or me.accuracy_m>75 then raise exception 'ACCURATE_LOCATION_REQUIRED';end if;
  if private.distance_meters(me.latitude,me.longitude,t.latitude,t.longitude)>greatest(30,least(me.accuracy_m,60)) then raise exception 'TOY_OUT_OF_RANGE';end if;
  insert into public.event_toy_collections(toy_id,player_id) values(t.id,uid) on conflict do nothing;if not found then raise exception 'TOY_ALREADY_COLLECTED';end if;
  insert into public.event_wallets(event_id,player_id,balance,lifetime_collected) values(ev.id,uid,1,1)
  on conflict(event_id,player_id) do update set balance=public.event_wallets.balance+1,lifetime_collected=public.event_wallets.lifetime_collected+1,updated_at=now() returning balance into bal;
  insert into public.player_event_log(player_id,category,title,details) values(uid,'other','Hittade en av Frasses leksaker',jsonb_build_object('toy_type',t.toy_type,'event_id',ev.id));
  return jsonb_build_object('toy_id',t.id,'toy_type',t.toy_type,'toy_balance',bal);
end $$;

create or replace function public.acknowledge_event_intro(p_event_id uuid,p_event_day date) returns void language sql security definer set search_path='' as $$
  insert into public.event_intro_seen(event_id,event_day,player_id) values(p_event_id,p_event_day,auth.uid()) on conflict do nothing
$$;
create or replace function public.buy_event_glow(p_color_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();ev uuid;bal integer;begin
  if p_color_id not in('gold','red','pink','purple','blue','cyan','green','lime','orange','white') then raise exception 'INVALID_GLOW';end if;
  select id into ev from public.game_events where event_type='frasse_escape' and active and now()<ends_at order by starts_at desc limit 1;if ev is null then raise exception 'EVENT_NOT_ACTIVE';end if;
  if exists(select 1 from public.player_marker_glows where player_id=uid and color_id=p_color_id) then update public.profiles set active_glow_color=p_color_id where id=uid;select balance into bal from public.event_wallets where event_id=ev and player_id=uid;return jsonb_build_object('toy_balance',coalesce(bal,0),'equipped_glow',p_color_id,'already_owned',true);end if;
  update public.event_wallets set balance=balance-100,updated_at=now() where event_id=ev and player_id=uid and balance>=100 returning balance into bal;if not found then raise exception 'NOT_ENOUGH_TOYS';end if;
  insert into public.player_marker_glows(player_id,color_id) values(uid,p_color_id);update public.profiles set active_glow_color=p_color_id where id=uid;
  return jsonb_build_object('toy_balance',bal,'equipped_glow',p_color_id,'already_owned',false);
end $$;
create or replace function public.equip_event_glow(p_color_id text) returns void language plpgsql security definer set search_path='' as $$begin
  if p_color_id='none' then update public.profiles set active_glow_color=null where id=auth.uid();
  elsif exists(select 1 from public.player_marker_glows where player_id=auth.uid() and color_id=p_color_id) then update public.profiles set active_glow_color=p_color_id where id=auth.uid();else raise exception 'GLOW_NOT_OWNED';end if;
end $$;

create or replace function public.admin_get_frasse_event() returns jsonb language plpgsql security definer set search_path='' as $$declare e public.game_events%rowtype;begin perform private.assert_admin(auth.uid());select * into e from public.game_events where event_type='frasse_escape' and active and ends_at>now() order by starts_at desc limit 1;return case when found then jsonb_build_object('active',true,'event_id',e.id,'starts_at',e.starts_at,'ends_at',e.ends_at) else jsonb_build_object('active',false) end;end $$;
create or replace function public.admin_set_frasse_event(p_enabled boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();eid uuid;begin perform private.assert_admin(uid);update public.game_events set active=false where event_type='frasse_escape' and active;
  if p_enabled then insert into public.game_events(event_type,title,story,active,starts_at,ends_at,activated_by) values('frasse_escape','FRASSE HAR RYMT!','Busfröet Frasse har rymt igen – och den här gången tog han med sig alla sina favoritleksaker. Men famnen blev alldeles för full. Nu ligger bollar, rep, gosedjur och pipleksaker utspridda över hela kartan. Hjälp Frasse att samla ihop dem innan dagen är slut! Klockan 07.00 i morgon rymmer han på nytt och tappar en helt ny omgång.','true',now(),now()+interval '7 days',uid) returning id into eid;end if;
  insert into public.admin_audit_log(admin_id,action,target_object_id,reason,details) values(uid,case when p_enabled then 'start_frasse_event' else 'stop_frasse_event' end,eid,'Veckoevent via admin',jsonb_build_object('duration_days',7));
  return public.admin_get_frasse_event();end $$;

revoke execute on function public.get_frasse_escape_event(double precision,double precision),public.claim_event_toy(uuid),public.acknowledge_event_intro(uuid,date),public.buy_event_glow(text),public.equip_event_glow(text),public.admin_get_frasse_event(),public.admin_set_frasse_event(boolean) from public,anon;
grant execute on function public.get_frasse_escape_event(double precision,double precision),public.claim_event_toy(uuid),public.acknowledge_event_intro(uuid,date),public.buy_event_glow(text),public.equip_event_glow(text) to authenticated;
grant execute on function public.admin_get_frasse_event(),public.admin_set_frasse_event(boolean) to authenticated;
notify pgrst,'reload schema';
