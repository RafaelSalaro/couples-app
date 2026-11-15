-- WP-4: what the Edge Functions and scheduled jobs need from the database: the outbox
-- queue, the waitlist, the web approve link, the scheduled jobs of docs/05 §4, realtime
-- broadcasts (docs/05 §5) and the pg_cron schedule. Conventions as in 20261113200000_minutes.sql.

-- ---------------------------------------------------------------------------
-- Outbox: claimed by the sender, one row at a time per worker
-- ---------------------------------------------------------------------------

-- Due rows with what the sender needs to address them. Claiming bumps attempts and pushes
-- send_after forward, so a crashed sender does not lose rows and two senders never share one.
create function public.claim_outbox(p_limit int default 100, p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rows jsonb;
begin
  with due as (
    select id from public.notifications_outbox
    where status = 'queued' and send_after <= p_now
    order by send_after, created_at
    limit greatest(1, least(p_limit, 500))
    for update skip locked
  ), claimed as (
    update public.notifications_outbox o
      set attempts = o.attempts + 1, send_after = p_now + interval '5 minutes'
      from due where o.id = due.id
      returning o.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'kind', c.kind, 'channel', c.channel, 'payload', c.payload, 'attempts', c.attempts,
    'email', (select u.email from auth.users u where u.id = c.user_id),
    'from_name', coalesce(
      (select display_name from public.profiles where id = (c.payload ->> 'from_user_id')::uuid),
      (select display_name from public.profiles where id = public.partner_of(c.user_id))),
    'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                        from public.push_tokens t where t.user_id = c.user_id), '[]'::jsonb)
  )), '[]'::jsonb) into v_rows
  from claimed c;
  return v_rows;
end $$;

-- Retry after a growing pause (1, 4, 9, 16 minutes); give up after the sender says so.
create function public.finish_outbox(p_id uuid, p_outcome text, p_now timestamptz default now())
returns void
language plpgsql set search_path = '' as $$
begin
  update public.notifications_outbox
    set status = case p_outcome when 'sent' then 'sent' when 'failed' then 'failed' else 'queued' end::public.outbox_status,
        send_after = case when p_outcome = 'retry' then p_now + make_interval(mins => attempts * attempts) else send_after end
    where id = p_id;
end $$;

-- Sent rows are kept a week for debugging, then removed (they may hold names or emails).
create function public.prune_outbox(p_now timestamptz default now()) returns int
language plpgsql set search_path = '' as $$
declare v_count int;
begin
  delete from public.notifications_outbox where status <> 'queued' and created_at < p_now - interval '7 days';
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- Waitlist (web/README.md contract): double opt-in, never reveals who is on the list
-- ---------------------------------------------------------------------------
create unique index if not exists waitlist_email_lower on public.waitlist (lower(email));

-- p_client_key: a hash of the caller's IP, for the rate limit (10 per hour).
create function public.api_waitlist_join(p_email text, p_source text, p_client_key text, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_token text := public.random_token();
  v_row public.waitlist;
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254 then perform public.fail('invalid_email'); end if;
  if not public.take_rate_limit('waitlist:' || coalesce(p_client_key, 'unknown'), 10, interval '1 hour', p_now) then
    perform public.fail('rate_limited');
  end if;
  insert into public.waitlist (email, source, created_at) values (v_email, left(p_source, 80), p_now)
    on conflict (lower(email)) do nothing;
  select * into v_row from public.waitlist where lower(email) = v_email for update;
  -- Confirmed already, or emailed in the last hour: answer the same, send nothing.
  if v_row.confirmed_at is not null or v_row.last_email_at > p_now - interval '1 hour' then
    return jsonb_build_object('joined', true);
  end if;
  update public.waitlist set confirm_token_hash = public.sha256_hex(v_token), last_email_at = p_now where id = v_row.id;
  insert into public.notifications_outbox (user_id, kind, payload, channel, send_after)
  values (null, 'waitlist_confirm', jsonb_build_object('email', v_email, 'token', v_token), 'email', p_now);
  return jsonb_build_object('joined', true);
end $$;

create function public.api_waitlist_confirm(p_token text, p_now timestamptz default now())
returns boolean
language plpgsql set search_path = '' as $$
begin
  update public.waitlist set confirmed_at = coalesce(confirmed_at, p_now), confirm_token_hash = null
    where confirm_token_hash = public.sha256_hex(coalesce(p_token, ''));
  return found;
end $$;

-- ---------------------------------------------------------------------------
-- The approve link in the fallback email (web page /approve/<token>, decision E8)
-- ---------------------------------------------------------------------------
create function public.api_respond_unlock_by_token(p_token text, p_approve boolean, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row public.unlock_requests;
  v_partner uuid;
begin
  select * into v_row from public.unlock_requests where approve_token_hash = public.sha256_hex(coalesce(p_token, ''));
  if not found then perform public.fail('invalid'); end if;
  select user_id into v_partner from public.pair_members
    where pair_id = v_row.pair_id and user_id <> v_row.requester_id and left_at is null;
  if v_partner is null then perform public.fail('invalid'); end if;
  return public.api_respond_unlock_request(v_partner, v_row.id, p_approve, p_now);
end $$;

-- ---------------------------------------------------------------------------
-- Scheduled jobs (docs/05 §4)
-- ---------------------------------------------------------------------------

-- Every minute: pending requests past 5 minutes expire and the requester hears so.
create function public.expire_requests(p_now timestamptz default now()) returns int
language plpgsql set search_path = '' as $$
declare
  v_count int := 0;
  r public.unlock_requests;
begin
  for r in select * from public.unlock_requests where status = 'pending' and expires_at <= p_now for update skip locked loop
    perform public.expire_unlock_request_if_due(r, p_now);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- Hourly: completions (48 h), reset proposals and schedule change requests (24 h).
create function public.expire_misc(p_now timestamptz default now()) returns int
language plpgsql set search_path = '' as $$
declare v_a int; v_b int; v_c int;
begin
  v_a := public.expire_completions(p_now);
  update public.reset_proposals set status = 'expired' where status = 'pending' and expires_at <= p_now;
  get diagnostics v_b = row_count;
  update public.schedule_change_requests set status = 'expired' where status = 'pending' and expires_at <= p_now;
  get diagnostics v_c = row_count;
  return v_a + v_b + v_c;
end $$;

-- Hourly: at 7 PM local, tell people whose minutes expire tomorrow (once per local day).
create function public.expiry_reminder(p_now timestamptz default now()) returns int
language plpgsql set search_path = '' as $$
declare
  v_count int := 0;
  r record;
begin
  for r in
    select p.id, p.time_zone, (p_now at time zone p.time_zone)::date as today,
           sum(l.remaining)::int as minutes
    from public.profiles p
    join public.minute_lots l on l.user_id = p.id and l.closed_at is null and l.remaining > 0
    where extract(hour from p_now at time zone p.time_zone) = 19
      and (l.expires_at at time zone p.time_zone)::date = (p_now at time zone p.time_zone)::date + 1
    group by p.id, p.time_zone
  loop
    continue when exists (
      select 1 from public.notifications_outbox
      where user_id = r.id and kind = 'minutes_expiring' and payload ->> 'day' = r.today::text);
    if public.enqueue_notification(r.id, 'minutes_expiring', jsonb_build_object('minutes', r.minutes, 'day', r.today)) is not null then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end $$;

-- The weekly report of a pair for the 7 local days starting p_week_start (Monday), in the
-- shape the app reads (WeeklyReport in ios/Packages/Core).
create function public.build_weekly_report(p_pair uuid, p_week_start date, p_time_zone text) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_from timestamptz := p_week_start::timestamp at time zone p_time_zone;
  v_to timestamptz := (p_week_start + 7)::timestamp at time zone p_time_zone;
  v_members jsonb := '{}'::jsonb;
  v_generous uuid;
  v_together int;
  v_shared int;
  v_hours int;
  m record;
begin
  for m in select user_id from public.pair_members where pair_id = p_pair loop
    v_members := v_members || jsonb_build_object(m.user_id::text, jsonb_build_object(
      'minutes_earned', (select coalesce(sum(minutes), 0) from public.minute_ledger
                         where user_id = m.user_id and pair_id = p_pair and created_at >= v_from and created_at < v_to
                           and type in ('earn_challenge', 'earn_kudos')),
      'minutes_spent', (select coalesce(-sum(minutes), 0) from public.minute_ledger
                        where user_id = m.user_id and pair_id = p_pair and created_at >= v_from and created_at < v_to
                          and type in ('spend_unlock', 'emergency_borrow')),
      'minutes_expired', (select coalesce(-sum(minutes), 0) from public.minute_ledger
                          where user_id = m.user_id and pair_id = p_pair and created_at >= v_from and created_at < v_to and type = 'expire'),
      'challenges_completed', (select count(*) from public.challenge_completions
                               where completed_by = m.user_id and pair_id = p_pair and status = 'confirmed'
                                 and confirmed_at >= v_from and confirmed_at < v_to),
      'requests_sent', (select count(*) from public.unlock_requests
                        where requester_id = m.user_id and pair_id = p_pair and created_at >= v_from and created_at < v_to),
      'requests_approved', (select count(*) from public.unlock_requests
                            where requester_id = m.user_id and pair_id = p_pair and status in ('approved', 'redeemed')
                              and created_at >= v_from and created_at < v_to),
      'kudos_given', (select count(*) from public.kudos where giver_id = m.user_id and pair_id = p_pair and created_at >= v_from and created_at < v_to),
      'kudos_received', (select count(*) from public.kudos where receiver_id = m.user_id and pair_id = p_pair and created_at >= v_from and created_at < v_to)));
  end loop;

  select coalesce(sum(minutes), 0)::int into v_together from public.minute_ledger
    where pair_id = p_pair and created_at >= v_from and created_at < v_to and type in ('earn_challenge', 'earn_kudos');
  select count(*)::int into v_shared from public.challenge_completions cc join public.challenges c on c.id = cc.challenge_id
    where cc.pair_id = p_pair and cc.status = 'confirmed' and c.is_shared and cc.confirmed_at >= v_from and cc.confirmed_at < v_to;
  select giver_id into v_generous from public.kudos where pair_id = p_pair and created_at >= v_from and created_at < v_to
    group by giver_id order by count(*) desc, giver_id limit 1;
  -- Protected hours this week, summed over both partners' schedules, hour by hour.
  select count(*)::int into v_hours
    from public.pair_members pm, generate_series(v_from, v_to - interval '1 hour', interval '1 hour') h
    where pm.pair_id = p_pair and public.is_protected(pm.user_id, h + interval '30 minutes');

  return jsonb_build_object(
    'members', v_members, 'total_earned_together', v_together, 'shared_challenges_done', v_shared,
    'protected_hours', v_hours, 'streak', coalesce((select current_length from public.streaks where pair_id = p_pair), 0),
    'most_generous_user_id', v_generous);
end $$;

-- Hourly on Sundays: at 7 PM local (the earlier of the two partners' zones), store the
-- week's report and tell both.
create function public.weekly_reports_job(p_now timestamptz default now()) returns int
language plpgsql set search_path = '' as $$
declare
  v_count int := 0;
  r record;
  v_week date;
  m record;
begin
  for r in
    select pr.id as pair_id, pf.time_zone
    from public.pairs pr
    join lateral (
      select p.time_zone from public.pair_members pm join public.profiles p on p.id = pm.user_id
      where pm.pair_id = pr.id and pm.left_at is null
      order by (p_now at time zone p.time_zone) desc limit 1) pf on true
    where pr.status = 'active'
      and extract(isodow from p_now at time zone pf.time_zone) = 7
      and extract(hour from p_now at time zone pf.time_zone) = 19
  loop
    v_week := (p_now at time zone r.time_zone)::date - 6;
    continue when exists (select 1 from public.weekly_reports where pair_id = r.pair_id and week_start = v_week);
    insert into public.weekly_reports (pair_id, week_start, data, created_at)
    values (r.pair_id, v_week, public.build_weekly_report(r.pair_id, v_week, r.time_zone), p_now);
    for m in select user_id from public.pair_members where pair_id = r.pair_id and left_at is null loop
      perform public.enqueue_notification(m.user_id, 'weekly_report', jsonb_build_object('pair_id', r.pair_id, 'week_start', v_week));
      perform public.enqueue_notification(m.user_id, 'weekly_report_email', jsonb_build_object(
        'pair_id', r.pair_id, 'week_start', v_week, 'from_user_id', public.partner_of(m.user_id),
        'earned', (select data -> 'members' -> m.user_id::text ->> 'minutes_earned' from public.weekly_reports where pair_id = r.pair_id and week_start = v_week),
        'together', (select data ->> 'total_earned_together' from public.weekly_reports where pair_id = r.pair_id and week_start = v_week),
        'streak', (select current_length from public.streaks where pair_id = r.pair_id)), 'email');
    end loop;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- Realtime (docs/05 §5): a "change" broadcast on pair:<pair_id> with {table, id} only. The
-- app then reads the row through RLS, so no content travels on the channel.
-- ---------------------------------------------------------------------------
create function public.broadcast_pair_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_row jsonb := to_jsonb(coalesce(new, old));
  v_pairs uuid[];
  v_pair uuid;
begin
  v_pairs := case
    when v_row ? 'pair_id' and v_row ->> 'pair_id' is not null then array[(v_row ->> 'pair_id')::uuid]
    when tg_table_name = 'pairs' then array[(v_row ->> 'id')::uuid]
    when tg_table_name = 'profiles' then array(select pair_id from public.pair_members where user_id = (v_row ->> 'id')::uuid and left_at is null)
    when v_row ? 'user_id' then array(select pair_id from public.pair_members where user_id = (v_row ->> 'user_id')::uuid and left_at is null)
    else '{}'::uuid[] end;
  foreach v_pair in array coalesce(v_pairs, '{}') loop
    perform realtime.send(
      jsonb_build_object('table', tg_table_name, 'id', coalesce(v_row ->> 'id', v_row ->> 'pair_id')),
      'change', 'pair:' || v_pair::text, false);
  end loop;
  return null;
exception when others then
  -- Realtime is a convenience: a failed broadcast must never undo the change itself.
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['unlock_requests', 'challenge_completions', 'challenges', 'kudos', 'schedule_change_requests',
                           'reset_proposals', 'streaks', 'minute_ledger', 'pairs', 'pair_members', 'pair_coverage',
                           'entitlements', 'pair_secrets', 'profiles'] loop
    execute format('create trigger %I after insert or update or delete on public.%I
                    for each row execute function public.broadcast_pair_change()', t || '_broadcast', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- pg_cron schedule
-- ---------------------------------------------------------------------------
create extension if not exists pg_cron;

select cron.schedule('expire_requests', '* * * * *', $$select public.expire_requests()$$);
select cron.schedule('expire_minutes', '5 * * * *', $$select public.expire_minutes()$$);
select cron.schedule('expire_misc', '10 * * * *', $$select public.expire_misc()$$);
select cron.schedule('streak_rollover', '15 * * * *', $$select public.streak_rollover()$$);
select cron.schedule('expiry_reminder', '0 * * * *', $$select public.expiry_reminder()$$);
select cron.schedule('weekly_report', '0 * * * 0,1', $$select public.weekly_reports_job()$$);
select cron.schedule('prune_outbox', '30 3 * * *', $$select public.prune_outbox()$$);

-- The sender runs as an Edge Function. pg_cron calls it every minute through pg_net with
-- the project URL and the cron secret kept in Vault (see supabase/README.md). Without those
-- secrets (local development) nothing is scheduled and `send_notifications` is run by hand.
create extension if not exists pg_net;
create function public.call_send_notifications() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_url text := (select decrypted_secret from vault.decrypted_secrets where name = 'functions_url');
  v_secret text := (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret');
begin
  if v_url is null or v_secret is null then return; end if;
  perform net.http_post(url := v_url || '/send_notifications',
                        headers := jsonb_build_object('content-type', 'application/json', 'x-cron-secret', v_secret),
                        body := '{}'::jsonb);
end $$;
select cron.schedule('send_notifications', '* * * * *', $$select public.call_send_notifications()$$);

-- ---------------------------------------------------------------------------
-- Account deletion removes the person's own ledger rows, which the service role may not
-- delete (the ledger is immutable for everyone else). Run it with the owner's rights.
-- Found by the Edge Function integration test: as the service role it failed with
-- "permission denied for table minute_ledger".
-- ---------------------------------------------------------------------------
alter function public.api_delete_account(uuid, timestamptz) security definer;
revoke execute on function public.api_delete_account(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.api_delete_account(uuid, timestamptz) to service_role;
