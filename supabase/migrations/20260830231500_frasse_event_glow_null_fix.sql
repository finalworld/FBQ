-- A profile without an active glow produced JSON null for every `equipped`
-- flag. Android correctly rejected that against its Boolean contract, which
-- made the whole active event look inactive. Always return a real boolean.
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

revoke execute on function public.get_frasse_escape_event(double precision,double precision) from public,anon;
grant execute on function public.get_frasse_escape_event(double precision,double precision) to authenticated;
notify pgrst,'reload schema';
