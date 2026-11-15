-- WP-3: core helpers, the minutes engine (grant / spend / borrow / expire / reset) and
-- streaks. Rules: docs/03-feature-spec.md §7 and §9, docs/05-data-model-and-api.md §1.
--
-- Conventions for every server function:
--   * Only the service role may execute them (Edge Functions). Clients never can.
--   * They take p_now (default now()) so tests can move the clock; Edge Functions never
--     pass it.
--   * Business errors are raised with SQLSTATE 'CAERR' and the error code as the message
--     (for example 'in_debt'). Edge Functions turn that into {ok:false, error:{code}}.
--   * Every change to a user's minutes first locks that user's minute_debt row, so
--     concurrent changes for one user run one after another. When two users are touched,
--     both rows are locked in user_id order (lock_minutes) to avoid deadlocks.

-- Functions created by postgres are not executable by PUBLIC anywhere (this default can
-- only be changed globally, not per schema).
alter default privileges for role postgres revoke execute on functions from public;

-- ---------------------------------------------------------------------------
-- Core helpers
-- ---------------------------------------------------------------------------
create function public.fail(p_code text) returns void
language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = 'CAERR', message = p_code;
end $$;

-- The user's local calendar day at p_now.
create function public.local_day(p_user uuid, p_now timestamptz default now()) returns date
language sql stable set search_path = '' as $$
  select (p_now at time zone coalesce(
    (select time_zone from public.profiles where id = p_user), 'UTC'))::date;
$$;

create function public.active_pair_of(p_user uuid) returns uuid
language sql stable set search_path = '' as $$
  select pm.pair_id from public.pair_members pm
  join public.pairs p on p.id = pm.pair_id and p.status = 'active'
  where pm.user_id = p_user and pm.left_at is null;
$$;

create function public.partner_of(p_user uuid) returns uuid
language sql stable set search_path = '' as $$
  select them.user_id
  from public.pair_members me
  join public.pairs p on p.id = me.pair_id and p.status = 'active'
  join public.pair_members them on them.pair_id = me.pair_id and them.user_id <> me.user_id
  where me.user_id = p_user and me.left_at is null and them.left_at is null
  limit 1;
$$;

-- Notification category of a kind; null = cannot be muted (spec §11).
create function public.notification_category(p_kind text) returns text
language sql immutable set search_path = '' as $$
  select case
    when p_kind in ('unlock_approved', 'unlock_declined', 'unlock_expired') then 'request_updates'
    when p_kind in ('challenge_done', 'challenge_confirmed', 'challenge_value_proposed',
                    'challenge_value_countered', 'challenge_value_approved') then 'challenges'
    when p_kind = 'kudos_received' then 'kudos'
    when p_kind in ('minutes_expiring', 'reset_proposed', 'reset_accepted', 'reset_declined') then 'minutes'
    when p_kind = 'weekly_report' then 'weekly_report'
    when p_kind = 'weekly_report_email' then 'weekly_report_email'
    when p_kind in ('emergency_used', 'unpaired', 'protected_time_off', 'protected_time_on') then 'partner_activity'
    else null
  end;
$$;

-- Queue a push or email. Respects the recipient's muted categories. Returns the outbox id
-- or null when muted.
create function public.enqueue_notification(
  p_user uuid, p_kind text, p_payload jsonb default '{}'::jsonb,
  p_channel public.outbox_channel default 'push', p_send_after timestamptz default now())
returns uuid
language plpgsql set search_path = '' as $$
declare
  v_category text := public.notification_category(p_kind);
  v_pref jsonb;
  v_id uuid;
begin
  if p_user is null then return null; end if;
  if v_category is not null then
    select notification_prefs -> v_category into v_pref from public.user_settings where user_id = p_user;
    if v_category = 'weekly_report_email' then
      -- Opt-in (decision P24): sent only when explicitly turned on.
      if v_pref is distinct from 'true'::jsonb then return null; end if;
    elsif v_pref = 'false'::jsonb then
      return null;
    end if;
  end if;
  insert into public.notifications_outbox (user_id, kind, payload, channel, send_after)
  values (p_user, p_kind, coalesce(p_payload, '{}'::jsonb), p_channel, p_send_after)
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Minutes engine
-- ---------------------------------------------------------------------------

-- Lock the minute_debt rows of the given users, in a fixed order.
create function public.lock_minutes(variadic p_users uuid[]) returns void
language plpgsql set search_path = '' as $$
begin
  insert into public.minute_debt (user_id)
  select u from unnest(p_users) u where u is not null
  on conflict (user_id) do nothing;
  perform 1 from public.minute_debt where user_id = any (p_users) order by user_id for update;
end $$;

-- Credit minutes: repay debt first; the remainder becomes a lot expiring in 7 days.
-- Returns the new lot's id, or null when the whole credit went to debt.
create function public.grant_minutes(
  p_user uuid, p_pair uuid, p_minutes int, p_type public.ledger_type,
  p_source_table text default null, p_source_id uuid default null,
  p_now timestamptz default now())
returns uuid
language plpgsql set search_path = '' as $$
declare
  v_debt int;
  v_repay int;
  v_rest int;
  v_lot uuid;
  v_day date := public.local_day(p_user, p_now);
begin
  if p_minutes is null or p_minutes <= 0 then perform public.fail('invalid_input'); end if;
  if p_type not in ('starting_grant', 'earn_challenge', 'earn_kudos', 'reset', 'admin_adjust') then
    perform public.fail('invalid_input');
  end if;
  perform public.lock_minutes(p_user);
  select debt into v_debt from public.minute_debt where user_id = p_user;

  v_repay := least(v_debt, p_minutes);
  if v_repay > 0 then
    update public.minute_debt set debt = debt - v_repay where user_id = p_user;
    insert into public.minute_ledger (user_id, pair_id, type, minutes, source_table, source_id, local_day, created_at)
    values (p_user, p_pair, 'debt_repay', v_repay, p_source_table, p_source_id, v_day, p_now);
  end if;

  v_rest := p_minutes - v_repay;
  if v_rest > 0 then
    insert into public.minute_lots (user_id, pair_id, granted, remaining, expires_at, created_at)
    values (p_user, p_pair, v_rest, v_rest, p_now + interval '7 days', p_now)
    returning id into v_lot;
    insert into public.minute_ledger (user_id, pair_id, type, minutes, lot_id, source_table, source_id, local_day, created_at)
    values (p_user, p_pair, p_type, v_rest, v_lot, p_source_table, p_source_id, v_day, p_now);
  end if;
  return v_lot;
end $$;

-- Take p_minutes out of the user's open lots, soonest-to-expire first, writing one
-- ledger row per lot touched. Returns how many minutes could not be covered.
-- Caller must hold the user's minutes lock.
create function public.consume_lots(
  p_user uuid, p_pair uuid, p_minutes int, p_type public.ledger_type,
  p_source_table text, p_source_id uuid, p_now timestamptz)
returns int
language plpgsql set search_path = '' as $$
declare
  v_left int := p_minutes;
  v_take int;
  v_day date := public.local_day(p_user, p_now);
  r record;
begin
  for r in
    select id, remaining from public.minute_lots
    where user_id = p_user and closed_at is null and remaining > 0 and expires_at > p_now
    order by expires_at, created_at, id
    for update
  loop
    exit when v_left <= 0;
    v_take := least(r.remaining, v_left);
    update public.minute_lots
      set remaining = remaining - v_take,
          closed_at = case when remaining - v_take = 0 then p_now else null end
      where id = r.id;
    insert into public.minute_ledger (user_id, pair_id, type, minutes, lot_id, source_table, source_id, local_day, created_at)
    values (p_user, p_pair, p_type, -v_take, r.id, p_source_table, p_source_id, v_day, p_now);
    v_left := v_left - v_take;
  end loop;
  return v_left;
end $$;

-- Minutes the user can spend right now (ignores debt).
create function public.available_minutes(p_user uuid, p_now timestamptz default now()) returns int
language sql stable set search_path = '' as $$
  select coalesce(sum(remaining), 0)::int from public.minute_lots
  where user_id = p_user and closed_at is null and expires_at > p_now;
$$;

-- Balance = available minutes minus debt (can be negative).
create function public.balance_of(p_user uuid, p_now timestamptz default now()) returns int
language sql stable set search_path = '' as $$
  select public.available_minutes(p_user, p_now)
       - coalesce((select debt from public.minute_debt where user_id = p_user), 0);
$$;

-- Minutes already spent on unlocks during the user's local day.
create function public.spent_today(p_user uuid, p_now timestamptz default now()) returns int
language sql stable set search_path = '' as $$
  select coalesce(-sum(minutes), 0)::int from public.minute_ledger
  where user_id = p_user and type = 'spend_unlock' and local_day = public.local_day(p_user, p_now);
$$;

-- Spend minutes on an unlock. Errors: in_debt, insufficient, over_daily_max.
create function public.spend_minutes(
  p_user uuid, p_pair uuid, p_minutes int, p_unlock_id uuid default null,
  p_now timestamptz default now())
returns void
language plpgsql set search_path = '' as $$
declare
  v_debt int;
  v_max int;
  v_left int;
begin
  if p_minutes is null or p_minutes <= 0 then perform public.fail('invalid_input'); end if;
  perform public.lock_minutes(p_user);
  select debt into v_debt from public.minute_debt where user_id = p_user;
  if v_debt > 0 then perform public.fail('in_debt'); end if;
  if public.available_minutes(p_user, p_now) < p_minutes then perform public.fail('insufficient'); end if;
  select coalesce((select daily_max_minutes from public.user_settings where user_id = p_user), 60) into v_max;
  if public.spent_today(p_user, p_now) + p_minutes > v_max then perform public.fail('over_daily_max'); end if;

  v_left := public.consume_lots(p_user, p_pair, p_minutes, 'spend_unlock', 'unlocks', p_unlock_id, p_now);
  if v_left <> 0 then
    raise exception 'spend_minutes: lots changed under lock (% left)', v_left;
  end if;
end $$;

-- Emergency borrow: takes what the balance has, the shortfall becomes debt.
-- Not limited by the daily maximum and allowed while already in debt.
create function public.borrow_minutes(
  p_user uuid, p_pair uuid, p_minutes int, p_unlock_id uuid default null,
  p_now timestamptz default now())
returns void
language plpgsql set search_path = '' as $$
declare
  v_left int;
begin
  if p_minutes is null or p_minutes <= 0 then perform public.fail('invalid_input'); end if;
  perform public.lock_minutes(p_user);
  v_left := public.consume_lots(p_user, p_pair, p_minutes, 'emergency_borrow', 'unlocks', p_unlock_id, p_now);
  if v_left > 0 then
    update public.minute_debt set debt = debt + v_left where user_id = p_user;
    insert into public.minute_ledger (user_id, pair_id, type, minutes, source_table, source_id, local_day, created_at)
    values (p_user, p_pair, 'emergency_borrow', -v_left, 'unlocks', p_unlock_id, public.local_day(p_user, p_now), p_now);
  end if;
end $$;

-- Close every lot that is past its expiry, writing an 'expire' ledger row for what was
-- left. Run hourly by pg_cron. Returns the number of lots expired.
create function public.expire_minutes(p_now timestamptz default now()) returns int
language plpgsql set search_path = '' as $$
declare
  v_count int := 0;
  u record;
  r record;
begin
  for u in
    select distinct user_id from public.minute_lots
    where closed_at is null and expires_at <= p_now
    order by user_id
  loop
    perform public.lock_minutes(u.user_id);
    for r in
      select id, pair_id, remaining from public.minute_lots
      where user_id = u.user_id and closed_at is null and expires_at <= p_now
      order by expires_at, id
      for update
    loop
      if r.remaining > 0 then
        insert into public.minute_ledger (user_id, pair_id, type, minutes, lot_id, local_day, created_at)
        values (u.user_id, r.pair_id, 'expire', -r.remaining, r.id, public.local_day(u.user_id, p_now), p_now);
        v_count := v_count + 1;
      end if;
      update public.minute_lots set remaining = 0, closed_at = p_now where id = r.id;
    end loop;
  end loop;
  return v_count;
end $$;

-- Bring a user's balance to exactly zero: remaining minutes are removed and debt is
-- forgiven, each as a 'reset' ledger row. Used by the mutual reset and by unpairing.
create function public.zero_balance(
  p_user uuid, p_pair uuid, p_source_table text, p_source_id uuid,
  p_now timestamptz default now())
returns void
language plpgsql set search_path = '' as $$
declare
  v_debt int;
  v_day date := public.local_day(p_user, p_now);
  r record;
begin
  perform public.lock_minutes(p_user);
  for r in
    select id, remaining, expires_at from public.minute_lots
    where user_id = p_user and closed_at is null
    order by expires_at, id
    for update
  loop
    if r.remaining > 0 then
      insert into public.minute_ledger (user_id, pair_id, type, minutes, lot_id, source_table, source_id, local_day, created_at)
      values (p_user, p_pair,
              case when r.expires_at <= p_now then 'expire' else 'reset' end::public.ledger_type,
              -r.remaining, r.id, p_source_table, p_source_id, v_day, p_now);
    end if;
    update public.minute_lots set remaining = 0, closed_at = p_now where id = r.id;
  end loop;

  select debt into v_debt from public.minute_debt where user_id = p_user;
  if v_debt > 0 then
    update public.minute_debt set debt = 0 where user_id = p_user;
    insert into public.minute_ledger (user_id, pair_id, type, minutes, source_table, source_id, local_day, created_at)
    values (p_user, p_pair, 'reset', v_debt, p_source_table, p_source_id, v_day, p_now);
  end if;
end $$;

-- Client-readable balances (own and partner's, through RLS on the underlying tables).
create view public.balances with (security_invoker = true) as
select d.user_id,
       coalesce(l.available, 0)::int - d.debt as balance,
       coalesce(l.available, 0)::int as available,
       d.debt
from public.minute_debt d
left join lateral (
  select sum(remaining) as available from public.minute_lots
  where user_id = d.user_id and closed_at is null and expires_at > now()
) l on true;
grant select on public.balances to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Mutual reset (spec §7.9): both partners must agree
-- ---------------------------------------------------------------------------
create function public.api_propose_reset(
  p_user uuid, p_standard_minutes int default null, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pair uuid := public.active_pair_of(p_user);
  v_partner uuid := public.partner_of(p_user);
  v_minutes int;
  v_row public.reset_proposals;
begin
  if v_pair is null or v_partner is null then perform public.fail('not_paired'); end if;
  perform 1 from public.pairs where id = v_pair for update;
  select coalesce(p_standard_minutes, standard_reset_minutes) into v_minutes from public.pairs where id = v_pair;
  -- TODO(product): allowed range for the standard amount is not in the docs (placeholder 0..60).
  if v_minutes < 0 or v_minutes > 60 then perform public.fail('invalid_input'); end if;

  update public.reset_proposals set status = 'expired'
    where pair_id = v_pair and status = 'pending' and expires_at <= p_now;
  if exists (select 1 from public.reset_proposals where pair_id = v_pair and status = 'pending') then
    perform public.fail('already_pending');
  end if;

  insert into public.reset_proposals (pair_id, proposer_id, standard_minutes, expires_at, created_at)
  values (v_pair, p_user, v_minutes, p_now + interval '24 hours', p_now)
  returning * into v_row;
  perform public.enqueue_notification(v_partner, 'reset_proposed',
    jsonb_build_object('proposal_id', v_row.id, 'pair_id', v_pair, 'from_user_id', p_user,
                       'standard_minutes', v_minutes));
  return to_jsonb(v_row);
end $$;

create function public.api_respond_reset(
  p_user uuid, p_proposal uuid, p_accept boolean, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row public.reset_proposals;
  v_member record;
begin
  select * into v_row from public.reset_proposals where id = p_proposal for update;
  if not found then perform public.fail('not_found'); end if;
  if v_row.proposer_id = p_user
     or public.active_pair_of(p_user) is distinct from v_row.pair_id then
    perform public.fail('not_partner');
  end if;
  if v_row.status <> 'pending' then
    if v_row.responded_by = p_user and (v_row.status = 'accepted') = p_accept then
      return to_jsonb(v_row);  -- same answer again: idempotent
    end if;
    perform public.fail(case when v_row.status = 'expired' then 'expired' else 'already_responded' end);
  end if;
  if v_row.expires_at <= p_now then
    update public.reset_proposals set status = 'expired' where id = p_proposal;
    -- Returned, not raised: the status change must persist.
    return jsonb_build_object('error', 'expired');
  end if;

  update public.reset_proposals
    set status = case when p_accept then 'accepted' else 'declined' end::public.reset_status,
        responded_by = p_user, responded_at = p_now
    where id = p_proposal
    returning * into v_row;

  if p_accept then
    perform public.lock_minutes(variadic array[p_user, v_row.proposer_id]);
    for v_member in
      select user_id from public.pair_members
      where pair_id = v_row.pair_id and left_at is null order by user_id
    loop
      perform public.zero_balance(v_member.user_id, v_row.pair_id, 'reset_proposals', v_row.id, p_now);
      if v_row.standard_minutes > 0 then
        perform public.grant_minutes(v_member.user_id, v_row.pair_id, v_row.standard_minutes,
                                     'reset', 'reset_proposals', v_row.id, p_now);
      end if;
    end loop;
    update public.pairs set standard_reset_minutes = v_row.standard_minutes where id = v_row.pair_id;
  end if;

  perform public.enqueue_notification(v_row.proposer_id,
    case when p_accept then 'reset_accepted' else 'reset_declined' end,
    jsonb_build_object('proposal_id', v_row.id, 'pair_id', v_row.pair_id, 'from_user_id', p_user,
                       'standard_minutes', v_row.standard_minutes));
  return to_jsonb(v_row);
end $$;

-- ---------------------------------------------------------------------------
-- Streaks (spec §9)
-- ---------------------------------------------------------------------------

-- Mark a day as breaking the pair's shared streak. The streak drops to zero right away
-- ("New streak starts today"); the broken day itself is not counted at rollover.
create function public.mark_streak_break(
  p_pair uuid, p_day date, p_reason public.streak_break_reason)
returns void
language plpgsql set search_path = '' as $$
begin
  if p_pair is null then return; end if;
  insert into public.daily_pair_status (pair_id, day, broke_streak, reason)
  values (p_pair, p_day, true, p_reason)
  on conflict (pair_id, day) do update
    set broke_streak = true, reason = coalesce(public.daily_pair_status.reason, excluded.reason);
  insert into public.streaks (pair_id) values (p_pair) on conflict do nothing;
  update public.streaks set current_length = 0, started_on = null where pair_id = p_pair;
end $$;

-- True when protected time is off for the user: the phone reported it off, or the user
-- has no enabled schedule.
create function public.protected_time_is_off(p_user uuid) returns boolean
language sql stable set search_path = '' as $$
  select coalesce((select protected_time_off_since is not null from public.profiles where id = p_user), false)
      or not exists (select 1 from public.schedules where user_id = p_user and enabled);
$$;

-- Count finished days. A pair's day is finished once it is over in both partners' time
-- zones. Each finished day either extends the streak or (if it was marked broken, or
-- protected time is off for a partner) resets it. Run hourly by pg_cron; safe to re-run.
-- Returns the number of pair-days processed.
create function public.streak_rollover(p_now timestamptz default now()) returns int
language plpgsql set search_path = '' as $$
declare
  v_count int := 0;
  p record;
  s public.streaks;
  v_day date;
  v_broken boolean;
  v_off boolean;
begin
  for p in
    select pr.id as pair_id,
           min((p_now at time zone pf.time_zone)::date) as today,
           min((pr.created_at at time zone pf.time_zone)::date) as first_day,
           count(*) as members
    from public.pairs pr
    join public.pair_members pm on pm.pair_id = pr.id and pm.left_at is null
    join public.profiles pf on pf.id = pm.user_id
    where pr.status = 'active'
    group by pr.id
  loop
    continue when p.members < 2;
    insert into public.streaks (pair_id) values (p.pair_id) on conflict do nothing;
    select * into s from public.streaks where pair_id = p.pair_id for update;
    v_day := coalesce(s.last_counted_day + 1, p.first_day);
    continue when v_day >= p.today;

    select coalesce(bool_or(public.protected_time_is_off(pm.user_id)), false) into v_off
      from public.pair_members pm where pm.pair_id = p.pair_id and pm.left_at is null;

    while v_day < p.today loop
      select coalesce(bool_or(broke_streak), false) into v_broken
        from public.daily_pair_status where pair_id = p.pair_id and day = v_day;
      if not v_broken and v_off then
        insert into public.daily_pair_status (pair_id, day, broke_streak, reason)
        values (p.pair_id, v_day, true, 'protected_time_off')
        on conflict (pair_id, day) do update set broke_streak = true, reason = 'protected_time_off';
        v_broken := true;
      end if;
      if v_broken then
        s.current_length := 0;
        s.started_on := null;
      else
        insert into public.daily_pair_status (pair_id, day, broke_streak)
        values (p.pair_id, v_day, false) on conflict do nothing;
        s.current_length := s.current_length + 1;
        s.started_on := coalesce(s.started_on, v_day);
        s.best_length := greatest(s.best_length, s.current_length);
      end if;
      s.last_counted_day := v_day;
      v_day := v_day + 1;
      v_count := v_count + 1;
    end loop;

    update public.streaks
      set current_length = s.current_length, best_length = s.best_length,
          last_counted_day = s.last_counted_day, started_on = s.started_on
      where pair_id = p.pair_id;
  end loop;
  return v_count;
end $$;

-- pg_cron jobs are scheduled in a later migration together with the other jobs.
