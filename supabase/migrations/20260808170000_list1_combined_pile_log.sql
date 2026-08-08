-- Lista 1: show a dirt-pile purchase and its reward as one private log event.
create or replace function private.log_bone_ledger_event()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_claim public.pile_claims%rowtype;
  v_title text;
begin
  -- The matching reward entry contains the claim id. Logging the cost separately
  -- would create two rows for one player action.
  if new.reason = 'dirt_pile_cost' then
    return new;
  end if;

  if new.reason = 'dirt_pile_reward' then
    select * into v_claim
    from public.pile_claims
    where id = new.source_id
    limit 1;

    insert into public.player_event_log(
      player_id,category,title,bone_delta,xp_delta,details,source_id,created_at
    ) values (
      new.player_id,
      'pile',
      'Jordhög',
      coalesce(v_claim.reward_value, new.amount) - coalesce(v_claim.cost, 0),
      0,
      jsonb_build_object(
        'cost', coalesce(v_claim.cost, 0),
        'reward', coalesce(v_claim.reward_value, new.amount),
        'bone_type', v_claim.bone_type,
        'quantity', coalesce(v_claim.quantity, 1),
        'balance_after', new.balance_after
      ),
      new.source_id,
      new.created_at
    );
    return new;
  end if;

  v_title := case new.reason
    when 'loose_bone_collect' then 'Ben'
    when 'home_slot_stake' then 'Hemmaautomat – insats'
    when 'home_slot_payout' then 'Hemmaautomat – vinst'
    when 'walking_reward' then 'Promenad'
    else initcap(replace(new.reason, '_', ' '))
  end;

  insert into public.player_event_log(
    player_id,category,title,bone_delta,xp_delta,details,source_id,created_at
  ) values (
    new.player_id,
    case
      when new.reason like '%shop%' then 'purchase'
      when new.reason like '%walk%' then 'walking'
      else 'bone'
    end,
    v_title,
    new.amount,
    0,
    jsonb_build_object('balance_after', new.balance_after),
    new.source_id,
    new.created_at
  );
  return new;
end;
$$;
