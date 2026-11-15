-- WP-3: schedules and their approval flow, challenges, kudos, export and account deletion.
-- Conventions as in 20261113200000_minutes.sql.

-- ---------------------------------------------------------------------------
-- Schedules (spec §4)
-- ---------------------------------------------------------------------------

-- Whether one schedule protects the instant p_at. A window starts on each listed weekday
-- (1 = Monday) at start_local in the user's zone and ends at end_local, the next day when
-- end_local <= start_local. Local times are turned into instants by Postgres, so daylight
-- saving days are handled (a window simply has 23 or 25 hours that night).
create function public.schedule_protects(
  p_weekdays smallint[], p_start time, p_end time, p_time_zone text, p_at timestamptz)
returns boolean
language plpgsql stable set search_path = '' as $$
declare
  v_local_date date := (p_at at time zone p_time_zone)::date;
  v_day date;
  v_from timestamptz;
  v_to timestamptz;
begin
  foreach v_day in array array[v_local_date - 1, v_local_date] loop
    continue when not (extract(isodow from v_day)::smallint = any (p_weekdays));
    v_from := (v_day + p_start) at time zone p_time_zone;
    v_to := ((v_day + case when p_end <= p_start then 1 else 0 end) + p_end) at time zone p_time_zone;
    if p_at >= v_from and p_at < v_to then return true; end if;
  end loop;
  return false;
end $$;

-- Whether any enabled schedule of the user protects p_at.
create function public.is_protected(p_user uuid, p_at timestamptz default now()) returns boolean
language sql stable set search_path = '' as $$
  select exists (
    select 1 from public.schedules s join public.profiles p on p.id = s.user_id
    where s.user_id = p_user and s.enabled
      and public.schedule_protects(s.weekdays, s.start_local, s.end_local, p.time_zone, p_at));
$$;

-- The minutes of a week (0 = Monday 00:00 .. 10079) a schedule covers, as plain local time.
-- Used only to compare a schedule before and after a change.
create function public.week_minutes(p_enabled boolean, p_weekdays smallint[], p_start time, p_end time)
returns setof int
language sql immutable set search_path = '' as $$
  select ((d - 1) * 1440 + m) % 10080
  from unnest(case when p_enabled then p_weekdays else '{}'::smallint[] end) d,
       generate_series(
         (extract(epoch from p_start) / 60)::int,
         (extract(epoch from p_end) / 60)::int + case when p_end <= p_start then 1440 else 0 end - 1) m;
$$;

-- 'stricter' (covers at least everything it did, and more), 'looser' (any covered minute is
-- lost) or 'same'. p_old null means a new schedule, which is always stricter.
create function public.classify_schedule_change(
  p_old public.schedules, p_enabled boolean, p_weekdays smallint[], p_start time, p_end time)
returns text
language plpgsql immutable set search_path = '' as $$
begin
  if p_old.id is null then return 'stricter'; end if;
  if exists (
    select public.week_minutes(p_old.enabled, p_old.weekdays, p_old.start_local, p_old.end_local)
    except
    select public.week_minutes(p_enabled, p_weekdays, p_start, p_end)) then
    return 'looser';
  end if;
  if exists (
    select public.week_minutes(p_enabled, p_weekdays, p_start, p_end)
    except
    select public.week_minutes(p_old.enabled, p_old.weekdays, p_old.start_local, p_old.end_local)) then
    return 'stricter';
  end if;
  return 'same';
end $$;

-- Apply an approved or directly-allowed proposal. Returns the schedule row (null when removed).
create function public.apply_schedule_proposal(p_user uuid, p_schedule uuid, p_proposed jsonb, p_now timestamptz)
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_s jsonb := p_proposed -> 'schedule';
  v_row public.schedules;
begin
  case p_proposed ->> 'kind'
    when 'remove_schedule' then
      delete from public.schedules where id = p_schedule and user_id = p_user;
      return null;
    when 'fewer_paused_apps' then
      return null;  -- applied on the phone; nothing is stored here
    else
      if p_schedule is null then
        insert into public.schedules (user_id, name, weekdays, start_local, end_local, enabled, created_at, updated_at)
        values (p_user, coalesce(v_s ->> 'name', ''),
                array(select jsonb_array_elements_text(v_s -> 'weekdays')::smallint),
                (v_s ->> 'start_local')::time, (v_s ->> 'end_local')::time,
                coalesce((v_s ->> 'enabled')::boolean, true), p_now, p_now)
        returning * into v_row;
      else
        update public.schedules
          set name = coalesce(v_s ->> 'name', name),
              weekdays = array(select jsonb_array_elements_text(v_s -> 'weekdays')::smallint),
              start_local = (v_s ->> 'start_local')::time, end_local = (v_s ->> 'end_local')::time,
              enabled = coalesce((v_s ->> 'enabled')::boolean, true)
          where id = p_schedule and user_id = p_user
          returning * into v_row;
      end if;
      return to_jsonb(v_row);
  end case;
end $$;

-- Stricter changes apply now; looser ones (and every change while paired that removes
-- protection, including pausing fewer apps) wait for the partner, 24 hours. Unpaired: all
-- changes apply now. Free: 1 schedule; premium: up to 3.
-- Returns {applied: true, schedule} or {applied: false, request}.
create function public.api_propose_schedule_change(
  p_user uuid, p_schedule uuid, p_proposed jsonb, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_kind text := p_proposed ->> 'kind';
  v_s jsonb := p_proposed -> 'schedule';
  v_old public.schedules;
  v_pair uuid := public.active_pair_of(p_user);
  v_change text;
  v_weekdays smallint[];
  v_req public.schedule_change_requests;
begin
  if v_kind not in ('schedule', 'remove_schedule', 'fewer_paused_apps') then perform public.fail('invalid_input'); end if;
  if p_schedule is not null then
    select * into v_old from public.schedules where id = p_schedule and user_id = p_user for update;
    if not found then perform public.fail('not_found'); end if;
  end if;

  if v_kind = 'schedule' then
    begin
      v_weekdays := array(select jsonb_array_elements_text(v_s -> 'weekdays')::smallint);
      perform (v_s ->> 'start_local')::time, (v_s ->> 'end_local')::time;
    exception when others then
      perform public.fail('invalid_input');
    end;
    if v_s ->> 'start_local' is null or v_s ->> 'end_local' is null
       or cardinality(v_weekdays) = 0 or not (v_weekdays <@ array[1,2,3,4,5,6,7]::smallint[]) then
      perform public.fail('invalid_input');
    end if;
    if p_schedule is null and (select count(*) from public.schedules where user_id = p_user)
         >= (case when public.is_premium(p_user, p_now) then 3 else 1 end) then
      perform public.fail('premium_required');
    end if;
    v_change := public.classify_schedule_change(v_old, coalesce((v_s ->> 'enabled')::boolean, true), v_weekdays,
                                                (v_s ->> 'start_local')::time, (v_s ->> 'end_local')::time);
  elsif v_kind = 'remove_schedule' then
    if p_schedule is null then perform public.fail('invalid_input'); end if;
    v_change := case when v_old.enabled then 'looser' else 'same' end;
  else
    v_change := 'looser';  -- the phone only asks when it pauses fewer apps
  end if;

  if v_pair is null or v_change <> 'looser' then
    return jsonb_build_object('applied', true, 'schedule', public.apply_schedule_proposal(p_user, p_schedule, p_proposed, p_now));
  end if;

  update public.schedule_change_requests set status = 'expired'
    where requester_id = p_user and status = 'pending' and expires_at <= p_now;
  insert into public.schedule_change_requests (pair_id, requester_id, schedule_id, proposed, expires_at, created_at)
  values (v_pair, p_user, p_schedule, p_proposed, p_now + interval '24 hours', p_now)
  returning * into v_req;
  perform public.enqueue_notification(public.partner_of(p_user), 'schedule_change_requested',
    jsonb_build_object('request_id', v_req.id, 'from_user_id', p_user, 'proposed', p_proposed));
  return jsonb_build_object('applied', false, 'request', to_jsonb(v_req));
end $$;

create function public.api_respond_schedule_change(
  p_user uuid, p_request uuid, p_approve boolean, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_req public.schedule_change_requests;
  v_schedule jsonb;
begin
  select * into v_req from public.schedule_change_requests where id = p_request for update;
  if not found then perform public.fail('not_found'); end if;
  if v_req.requester_id = p_user or public.active_pair_of(p_user) is distinct from v_req.pair_id then
    perform public.fail('not_partner');
  end if;
  if v_req.status = 'pending' and v_req.expires_at <= p_now then
    update public.schedule_change_requests set status = 'expired' where id = p_request;
    return jsonb_build_object('error', 'expired');
  end if;
  if v_req.status <> 'pending' then
    if v_req.responded_by = p_user and (v_req.status = 'approved') = p_approve then
      return jsonb_build_object('request', to_jsonb(v_req));
    end if;
    perform public.fail(case when v_req.status = 'expired' then 'expired' else 'already_responded' end);
  end if;

  update public.schedule_change_requests
    set status = case when p_approve then 'approved' else 'declined' end::public.change_request_status,
        responded_by = p_user, responded_at = p_now
    where id = p_request returning * into v_req;
  if p_approve then
    v_schedule := public.apply_schedule_proposal(v_req.requester_id, v_req.schedule_id, v_req.proposed, p_now);
  end if;
  perform public.enqueue_notification(v_req.requester_id,
    case when p_approve then 'schedule_change_approved' else 'schedule_change_declined' end,
    jsonb_build_object('request_id', v_req.id, 'from_user_id', p_user, 'proposed', v_req.proposed));
  return jsonb_build_object('request', to_jsonb(v_req), 'schedule', v_schedule);
end $$;

-- ---------------------------------------------------------------------------
-- Challenges and kudos (spec §8)
-- ---------------------------------------------------------------------------

-- A challenge the pair may use: a free preset; a premium preset with premium; or the
-- pair's own active custom challenge with premium.
create function public.challenge_usable(p_challenge public.challenges, p_pair uuid, p_premium boolean)
returns boolean
language sql immutable set search_path = '' as $$
  select p_challenge.status = 'active'
     and ((p_challenge.pair_id is null and (p_challenge.tier = 'free' or p_premium))
          or (p_challenge.pair_id = p_pair and p_premium));
$$;

create function public.api_complete_challenge(
  p_user uuid, p_challenge uuid, p_note text default null, p_photo_path text default null,
  p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pair uuid := public.active_pair_of(p_user);
  v_ch public.challenges;
  v_row public.challenge_completions;
begin
  if v_pair is null then perform public.fail('not_paired'); end if;
  select * into v_ch from public.challenges where id = p_challenge;
  if not found then perform public.fail('not_found'); end if;
  if not public.challenge_usable(v_ch, v_pair, public.is_premium(p_user, p_now)) then
    perform public.fail('premium_required');
  end if;
  -- A completion still open for this person and challenge is returned, not doubled.
  update public.challenge_completions set status = 'expired'
    where challenge_id = p_challenge and completed_by = p_user and status = 'awaiting_confirmation' and expires_at <= p_now;
  select * into v_row from public.challenge_completions
    where challenge_id = p_challenge and completed_by = p_user and status = 'awaiting_confirmation';
  if found then return to_jsonb(v_row); end if;

  insert into public.challenge_completions (challenge_id, pair_id, completed_by, note, photo_path, expires_at, created_at)
  values (p_challenge, v_pair, p_user, nullif(btrim(p_note), ''), p_photo_path, p_now + interval '48 hours', p_now)
  returning * into v_row;
  perform public.enqueue_notification(public.partner_of(p_user), 'challenge_done',
    jsonb_build_object('completion_id', v_row.id, 'challenge_id', p_challenge, 'from_user_id', p_user, 'title', v_ch.title));
  return to_jsonb(v_row);
end $$;

-- The partner confirms with one tap; minutes are granted then (to both for a shared one).
create function public.api_confirm_completion(p_user uuid, p_completion uuid, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row public.challenge_completions;
  v_ch public.challenges;
begin
  select * into v_row from public.challenge_completions where id = p_completion for update;
  if not found then perform public.fail('not_found'); end if;
  if v_row.completed_by = p_user or public.active_pair_of(p_user) is distinct from v_row.pair_id then
    perform public.fail('not_partner');
  end if;
  if v_row.status = 'confirmed' then return to_jsonb(v_row); end if;  -- idempotent
  if v_row.status = 'expired' or v_row.expires_at <= p_now then
    update public.challenge_completions set status = 'expired' where id = p_completion;
    return jsonb_build_object('error', 'expired');
  end if;
  select * into v_ch from public.challenges where id = v_row.challenge_id;

  update public.challenge_completions set status = 'confirmed', confirmed_by = p_user, confirmed_at = p_now
    where id = p_completion returning * into v_row;
  perform public.lock_minutes(variadic array[v_row.completed_by, p_user]);
  perform public.grant_minutes(v_row.completed_by, v_row.pair_id, v_ch.minutes, 'earn_challenge',
                               'challenge_completions', v_row.id, p_now);
  if v_ch.is_shared then
    perform public.grant_minutes(p_user, v_row.pair_id, v_ch.minutes, 'earn_challenge',
                                 'challenge_completions', v_row.id, p_now);
  end if;
  perform public.enqueue_notification(v_row.completed_by, 'challenge_confirmed',
    jsonb_build_object('completion_id', v_row.id, 'challenge_id', v_ch.id, 'from_user_id', p_user, 'minutes', v_ch.minutes));
  return to_jsonb(v_row);
end $$;

-- Kudos (premium): 5–30 minutes, at most 60 given per giver per local day.
create function public.api_give_kudos(
  p_user uuid, p_minutes int, p_message text default '', p_challenge uuid default null,
  p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pair uuid := public.active_pair_of(p_user);
  v_partner uuid := public.partner_of(p_user);
  v_day date := public.local_day(p_user, p_now);
  v_row public.kudos;
begin
  if v_pair is null or v_partner is null then perform public.fail('not_paired'); end if;
  if not public.is_premium(p_user, p_now) then perform public.fail('premium_required'); end if;
  if p_minutes is null or p_minutes not between 5 and 30 or char_length(p_message) > 140 then
    perform public.fail('invalid_input');
  end if;
  perform public.lock_minutes(variadic array[p_user, v_partner]);
  if coalesce((select sum(minutes) from public.kudos where giver_id = p_user and local_day = v_day), 0) + p_minutes > 60 then
    perform public.fail('daily_cap');
  end if;
  insert into public.kudos (pair_id, giver_id, receiver_id, challenge_id, message, minutes, local_day, created_at)
  values (v_pair, p_user, v_partner, p_challenge, coalesce(btrim(p_message), ''), p_minutes, v_day, p_now)
  returning * into v_row;
  perform public.grant_minutes(v_partner, v_pair, p_minutes, 'earn_kudos', 'kudos', v_row.id, p_now);
  perform public.enqueue_notification(v_partner, 'kudos_received',
    jsonb_build_object('kudos_id', v_row.id, 'from_user_id', p_user, 'minutes', p_minutes, 'message', v_row.message));
  return to_jsonb(v_row);
end $$;

-- Custom challenge (premium): the partner approves the value or suggests another.
create function public.api_create_custom_challenge(
  p_user uuid, p_title text, p_description text, p_minutes int,
  p_category public.challenge_category, p_is_shared boolean, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pair uuid := public.active_pair_of(p_user);
  v_row public.challenges;
begin
  if v_pair is null then perform public.fail('not_paired'); end if;
  if not public.is_premium(p_user, p_now) then perform public.fail('premium_required'); end if;
  if p_minutes is null or p_minutes not between 5 and 60 or char_length(btrim(coalesce(p_title, ''))) not between 1 and 80 then
    perform public.fail('invalid_input');
  end if;
  insert into public.challenges (pair_id, created_by, title, description, minutes, category, is_shared, tier,
                                 status, value_proposed_by, created_at)
  values (v_pair, p_user, btrim(p_title), coalesce(p_description, ''), p_minutes, p_category, coalesce(p_is_shared, false),
          'premium', 'pending_value_approval', p_user, p_now)
  returning * into v_row;
  perform public.enqueue_notification(public.partner_of(p_user), 'challenge_value_proposed',
    jsonb_build_object('challenge_id', v_row.id, 'from_user_id', p_user, 'title', v_row.title, 'minutes', p_minutes));
  return to_jsonb(v_row);
end $$;

-- Answer a proposed value: approve (the challenge becomes active) or counter with another
-- value, which the other partner then answers in turn.
create function public.api_respond_challenge_value(
  p_user uuid, p_challenge uuid, p_approve boolean, p_counter_minutes int default null,
  p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row public.challenges;
begin
  select * into v_row from public.challenges where id = p_challenge for update;
  if not found or v_row.pair_id is distinct from public.active_pair_of(p_user) then perform public.fail('not_found'); end if;
  if v_row.status <> 'pending_value_approval' then
    if v_row.status = 'active' and p_approve then return to_jsonb(v_row); end if;  -- idempotent
    perform public.fail('already_responded');
  end if;
  if v_row.value_proposed_by = p_user then perform public.fail('not_partner'); end if;

  if p_approve then
    update public.challenges set status = 'active' where id = p_challenge returning * into v_row;
    perform public.enqueue_notification(v_row.value_proposed_by, 'challenge_value_approved',
      jsonb_build_object('challenge_id', v_row.id, 'from_user_id', p_user, 'minutes', v_row.minutes));
  else
    if p_counter_minutes is null or p_counter_minutes not between 5 and 60 then perform public.fail('invalid_input'); end if;
    update public.challenges set minutes = p_counter_minutes, value_proposed_by = p_user
      where id = p_challenge returning * into v_row;
    perform public.enqueue_notification(public.partner_of(p_user), 'challenge_value_countered',
      jsonb_build_object('challenge_id', v_row.id, 'from_user_id', p_user, 'minutes', p_counter_minutes));
  end if;
  return to_jsonb(v_row);
end $$;

-- Hourly: completions not confirmed within 48 hours expire.
create function public.expire_completions(p_now timestamptz default now()) returns int
language plpgsql set search_path = '' as $$
declare v_count int;
begin
  update public.challenge_completions set status = 'expired'
    where status = 'awaiting_confirmation' and expires_at <= p_now;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- Export my data and account deletion (spec §13–14)
-- ---------------------------------------------------------------------------

-- Everything stored about the user. The partner's rows appear only where they are part of
-- the user's own history (requests, kudos), never the partner's own data.
create function public.api_export_my_data(p_user uuid) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'profile', (select to_jsonb(p) from public.profiles p where id = p_user),
    'settings', (select to_jsonb(s) from public.user_settings s where user_id = p_user),
    'schedules', coalesce((select jsonb_agg(to_jsonb(s)) from public.schedules s where user_id = p_user), '[]'),
    'pairs', coalesce((select jsonb_agg(to_jsonb(m)) from public.pair_members m where user_id = p_user), '[]'),
    'minute_ledger', coalesce((select jsonb_agg(to_jsonb(l) order by created_at) from public.minute_ledger l where user_id = p_user), '[]'),
    'unlocks', coalesce((select jsonb_agg(to_jsonb(u) order by started_at) from public.unlocks u where user_id = p_user), '[]'),
    'unlock_requests', coalesce((select jsonb_agg(to_jsonb(r) - 'code_hash' - 'approve_token_hash' order by created_at)
                                 from public.unlock_requests r where requester_id = p_user), '[]'),
    'challenge_completions', coalesce((select jsonb_agg(to_jsonb(c) order by created_at)
                                       from public.challenge_completions c where completed_by = p_user), '[]'),
    'kudos_given', coalesce((select jsonb_agg(to_jsonb(k) order by created_at) from public.kudos k where giver_id = p_user), '[]'),
    'kudos_received', coalesce((select jsonb_agg(to_jsonb(k) order by created_at) from public.kudos k where receiver_id = p_user), '[]'),
    'entitlements', coalesce((select jsonb_agg(to_jsonb(e)) from public.entitlements e where user_id = p_user), '[]'),
    'exported_at', now());
$$;

-- Unpair, then remove the person's data; their rows go with the profile (foreign keys
-- cascade). The partner keeps their own ledger, including minutes this person gave them.
-- The Edge Function deletes the auth user after this returns.
create function public.api_delete_account(p_user uuid, p_now timestamptz default now()) returns jsonb
language plpgsql set search_path = '' as $$
begin
  if public.active_pair_of(p_user) is not null then perform public.api_unpair(p_user, p_now); end if;
  perform public.lock_minutes(p_user);
  -- The ledger refuses updates; remove this person's rows explicitly first so cascades
  -- never need to rewrite them.
  delete from public.minute_ledger where user_id = p_user;
  delete from public.profiles where id = p_user;
  return jsonb_build_object('deleted', p_user);
end $$;
