-- 2026-11-15 founder testing (decisions P3, P14, P26–P30): the weekly emergency allowance,
-- ending any unlock early without losing time, and a required display name.
-- Conventions as in 20261113200000_minutes.sql.

-- Ledger rows for minutes returned when a minutes unlock ends early (P26).
alter type public.ledger_type add value if not exists 'unlock_refund';

-- ---------------------------------------------------------------------------
-- Settings: the weekly emergency allowance, chosen next to the daily maximum (P14)
-- ---------------------------------------------------------------------------
alter table public.user_settings
  add column emergency_allowance_minutes int not null default 15
    check (emergency_allowance_minutes in (15, 30, 45, 60));
grant update (emergency_allowance_minutes) on public.user_settings to authenticated;

-- When onboarding was finished, so a returning user (another phone, or after signing out)
-- skips what is already done (P29). Set by the app when onboarding finishes.
alter table public.user_settings add column onboarded_at timestamptz;
grant update (onboarded_at) on public.user_settings to authenticated;

-- ---------------------------------------------------------------------------
-- Unlocks can end early; an emergency session lasts whatever allowance is left
-- ---------------------------------------------------------------------------
alter table public.unlocks
  add column ended_early_at timestamptz,
  -- Whole minutes actually used (rounded up), set when the unlock ends early or, for an
  -- emergency session, when it is settled. Null while running.
  add column minutes_used int check (minutes_used >= 0);
alter table public.unlocks drop constraint unlocks_minutes_check;
alter table public.unlocks add constraint unlocks_minutes_check
  check (minutes > 0 and (method = 'emergency' or (minutes >= 15 and minutes % 15 = 0)));

-- ---------------------------------------------------------------------------
-- Name: required (what the partner sees); empty until the onboarding name step (P27)
-- ---------------------------------------------------------------------------
update public.profiles set display_name = '' where display_name is null;
alter table public.profiles alter column display_name set default '', alter column display_name set not null;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Sign in with Apple passes the name when the person shares it; email sign-in never does,
  -- and the app then asks "What should we call you?" right after sign-in.
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(left(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')), 60), ''))
  on conflict (id) do nothing;
  insert into public.user_settings (user_id) values (new.id) on conflict do nothing;
  insert into public.minute_debt (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The emergency allowance (P14)
-- ---------------------------------------------------------------------------

-- Minutes an unlock counts against an allowance: what was used once it has ended or been
-- settled, otherwise its full length (a running session reserves what it may still use).
create function public.unlock_minutes_counted(u public.unlocks) returns int
language sql immutable set search_path = '' as $$
  select coalesce(u.minutes_used, u.minutes);
$$;

-- The person's current emergency window: it starts at the first emergency use and lasts
-- 7 days; the next use after it ends starts a new window. Returns the start (null when no
-- window is open at p_now) and the minutes used in it.
create function public.emergency_window(p_user uuid, p_now timestamptz default now())
returns table (window_start timestamptz, used int)
language plpgsql stable set search_path = '' as $$
declare
  v_anchor timestamptz;
  r public.unlocks;
begin
  for r in select * from public.unlocks
           where user_id = p_user and method = 'emergency' and started_at <= p_now order by started_at loop
    if v_anchor is null or r.started_at >= v_anchor + interval '7 days' then v_anchor := r.started_at; end if;
  end loop;
  if v_anchor is null or p_now >= v_anchor + interval '7 days' then
    return query select null::timestamptz, 0;
    return;
  end if;
  return query
    select v_anchor, coalesce(sum(public.unlock_minutes_counted(u)), 0)::int
    from public.unlocks u
    where u.user_id = p_user and u.method = 'emergency' and u.started_at >= v_anchor and u.started_at <= p_now;
end $$;

-- What the unlock sheet shows: the allowance, what is used and left, and when it renews.
create function public.emergency_status(p_user uuid, p_now timestamptz default now()) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_allowance int := coalesce((select emergency_allowance_minutes from public.user_settings where user_id = p_user), 15);
  w record;
begin
  select * into w from public.emergency_window(p_user, p_now);
  return jsonb_build_object(
    'allowance', v_allowance, 'used', w.used, 'remaining', greatest(0, v_allowance - w.used),
    'renews_at', case when w.window_start is null then null else w.window_start + interval '7 days' end);
end $$;

-- Whole minutes between two instants, rounded up, at least 1.
create function public.whole_minutes_up(p_from timestamptz, p_to timestamptz) returns int
language sql immutable set search_path = '' as $$
  select greatest(1, ceil(extract(epoch from (p_to - p_from)) / 60.0)::int);
$$;

-- Emergency sessions that ran to their end borrow the minutes they lasted. Run before any
-- change to the person's minutes, and every minute by pg_cron. Returns the sessions settled.
create function public.settle_emergency_unlocks(p_user uuid, p_now timestamptz default now()) returns int
language plpgsql set search_path = '' as $$
declare
  v_count int := 0;
  r public.unlocks;
begin
  for r in select * from public.unlocks
           where user_id = p_user and method = 'emergency' and minutes_used is null and ends_at <= p_now
           order by started_at for update loop
    update public.unlocks set minutes_used = r.minutes where id = r.id;
    perform public.borrow_minutes(r.user_id, r.pair_id, r.minutes, r.id, r.ends_at);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

create function public.settle_all_emergency_unlocks(p_now timestamptz default now()) returns int
language plpgsql set search_path = '' as $$
declare
  v_count int := 0;
  u uuid;
begin
  for u in select distinct user_id from public.unlocks
           where method = 'emergency' and minutes_used is null and ends_at <= p_now loop
    v_count := v_count + public.settle_emergency_unlocks(u, p_now);
  end loop;
  return v_count;
end $$;
select cron.schedule('settle_emergency_unlocks', '* * * * *', $$select public.settle_all_emergency_unlocks()$$);

-- Start an emergency session for whatever allowance is left this week (§6.4). Nothing is
-- borrowed now: the minutes used are borrowed when the session ends. A running session is
-- returned as it is. The streak breaks once per day; the partner gets a note per session.
create or replace function public.api_emergency_unlock(
  p_user uuid, p_client_event_id uuid, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pair uuid := public.active_pair_of(p_user);
  v_unlock public.unlocks;
  v_status jsonb;
begin
  if p_client_event_id is null then perform public.fail('invalid_input'); end if;
  perform public.lock_minutes(p_user);
  select * into v_unlock from public.unlocks where client_event_id = p_client_event_id;
  if found then
    if v_unlock.user_id <> p_user then perform public.fail('invalid_input'); end if;
    return jsonb_build_object('unlock', to_jsonb(v_unlock), 'replayed', true, 'emergency', public.emergency_status(p_user, p_now));
  end if;
  perform public.settle_emergency_unlocks(p_user, p_now);
  select * into v_unlock from public.unlocks
    where user_id = p_user and method = 'emergency' and ended_early_at is null and started_at <= p_now and ends_at > p_now;
  if found then
    return jsonb_build_object('unlock', to_jsonb(v_unlock), 'replayed', true, 'emergency', public.emergency_status(p_user, p_now));
  end if;

  v_status := public.emergency_status(p_user, p_now);
  if (v_status ->> 'remaining')::int <= 0 then perform public.fail('allowance_used_up'); end if;
  v_unlock := public.new_unlock(p_user, v_pair, 'emergency', (v_status ->> 'remaining')::int, p_now, null, p_client_event_id);
  if v_pair is not null then
    perform public.mark_streak_break(v_pair, public.local_day(p_user, p_now), 'emergency');
    perform public.enqueue_notification(public.partner_of(p_user), 'emergency_used',
      jsonb_build_object('pair_id', v_pair, 'from_user_id', p_user));
  end if;
  return jsonb_build_object('unlock', to_jsonb(v_unlock), 'balance', public.balance_of(p_user, p_now),
                            'emergency', public.emergency_status(p_user, p_now));
end $$;

-- Minutes the unlock spent, returned to the lots they came from (keeping their expiry),
-- latest-expiring lot first; lots already expired are skipped. Returns the minutes refunded.
create function public.refund_unlock_minutes(p_user uuid, p_unlock uuid, p_minutes int, p_now timestamptz)
returns int
language plpgsql set search_path = '' as $$
declare
  v_left int := p_minutes;
  v_back int;
  r record;
begin
  for r in
    select l.lot_id, -sum(l.minutes)::int as spent, min(l.local_day) as local_day, lot.expires_at, lot.pair_id
    from public.minute_ledger l join public.minute_lots lot on lot.id = l.lot_id
    where l.user_id = p_user and l.source_id = p_unlock and l.type = 'spend_unlock'
    group by l.lot_id, lot.expires_at, lot.pair_id
    order by lot.expires_at desc
  loop
    exit when v_left <= 0;
    continue when r.expires_at <= p_now;
    v_back := least(r.spent, v_left);
    update public.minute_lots set remaining = remaining + v_back, closed_at = null where id = r.lot_id;
    insert into public.minute_ledger (user_id, pair_id, type, minutes, lot_id, source_table, source_id, local_day, created_at)
    values (p_user, r.pair_id, 'unlock_refund', v_back, r.lot_id, 'unlocks', p_unlock, r.local_day, p_now);
    v_left := v_left - v_back;
  end loop;
  return p_minutes - v_left;
end $$;

-- Minutes spent on unlocks during the local day, net of refunds from unlocks ended early.
-- (PL/pgSQL, not SQL: the new enum value cannot be checked inside the migration that adds it.)
create or replace function public.spent_today(p_user uuid, p_now timestamptz default now()) returns int
language plpgsql stable set search_path = '' as $$
begin
  return (select coalesce(-sum(minutes), 0)::int from public.minute_ledger
          where user_id = p_user and type::text in ('spend_unlock', 'unlock_refund')
            and local_day = public.local_day(p_user, p_now));
end $$;

-- End any running unlock early (§6, P26). Emergency: borrow only the minutes used and keep
-- the rest of the allowance. Minutes: refund the unused whole minutes. QR, partner approval
-- and accountability code: just end. Ending the same unlock again returns the same result.
create function public.api_end_unlock_early(p_user uuid, p_unlock uuid, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_unlock public.unlocks;
  v_used int;
  v_refunded int := 0;
begin
  perform public.lock_minutes(p_user);
  select * into v_unlock from public.unlocks where id = p_unlock and user_id = p_user for update;
  if not found then perform public.fail('not_found'); end if;
  if v_unlock.ended_early_at is not null then
    return jsonb_build_object('unlock', to_jsonb(v_unlock), 'replayed', true, 'emergency', public.emergency_status(p_user, p_now));
  end if;
  if not (v_unlock.started_at <= p_now and p_now < v_unlock.ends_at) then perform public.fail('not_active'); end if;

  v_used := least(v_unlock.minutes, public.whole_minutes_up(v_unlock.started_at, p_now));
  if v_unlock.method = 'emergency' then
    perform public.borrow_minutes(p_user, v_unlock.pair_id, v_used, v_unlock.id, p_now);
  elsif v_unlock.method = 'minutes' then
    v_refunded := public.refund_unlock_minutes(p_user, v_unlock.id,
                    floor(extract(epoch from (v_unlock.ends_at - p_now)) / 60)::int, p_now);
    v_used := v_unlock.minutes - v_refunded;
  end if;
  update public.unlocks set ended_early_at = p_now, ends_at = p_now, minutes_used = v_used
    where id = v_unlock.id returning * into v_unlock;
  return jsonb_build_object('unlock', to_jsonb(v_unlock), 'refunded', v_refunded,
                            'balance', public.balance_of(p_user, p_now), 'emergency', public.emergency_status(p_user, p_now));
end $$;

-- A finished emergency session must be settled before the person spends minutes.
create or replace function public.api_spend_minutes_unlock(
  p_user uuid, p_minutes int, p_client_event_id uuid, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pair uuid := public.active_pair_of(p_user);
  v_unlock public.unlocks;
begin
  if p_client_event_id is null then perform public.fail('invalid_input'); end if;
  perform public.lock_minutes(p_user);
  select * into v_unlock from public.unlocks where client_event_id = p_client_event_id;
  if found then
    if v_unlock.user_id <> p_user then perform public.fail('invalid_input'); end if;
    return jsonb_build_object('unlock', to_jsonb(v_unlock), 'replayed', true);
  end if;
  if not public.valid_unlock_length(p_minutes, public.is_premium(p_user, p_now)) then
    perform public.fail('invalid_input');
  end if;
  perform public.settle_emergency_unlocks(p_user, p_now);
  v_unlock := public.new_unlock(p_user, v_pair, 'minutes', p_minutes, p_now, null, p_client_event_id);
  perform public.spend_minutes(p_user, v_pair, p_minutes, v_unlock.id, p_now);
  return jsonb_build_object('unlock', to_jsonb(v_unlock), 'balance', public.balance_of(p_user, p_now));
end $$;
