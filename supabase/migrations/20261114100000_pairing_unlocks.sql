-- WP-3: premium coverage, pairing and unlocks as SQL functions. Each api_* function backs
-- one Edge Function of docs/05 §3 and follows the conventions in 20261113200000_minutes.sql
-- (service role only, p_now for tests, business errors as SQLSTATE 'CAERR').
--
-- Secrets: invite codes, link tokens, accountability codes and email approve tokens are
-- generated here, returned once to the caller (the Edge Function) and stored only as
-- SHA-256 hashes. The pair's QR secret is shared by both phones by design (each needs it
-- to show and to check codes), so current pair members may read it (decision E14).

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
create function public.sha256_hex(p_value text) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.digest(p_value, 'sha256'), 'hex');
$$;

-- RFC 4648 base32 without padding (what TOTP apps and the iPhone's QRCode package expect).
create function public.base32(p_bytes bytea) returns text
language plpgsql immutable set search_path = '' as $$
declare
  v_alphabet constant text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  v_bits text := '';
  v_out text := '';
  i int;
begin
  for i in 0 .. length(p_bytes) - 1 loop
    v_bits := v_bits || lpad(get_byte(p_bytes, i)::bit(8)::text, 8, '0');
  end loop;
  while length(v_bits) % 5 <> 0 loop v_bits := v_bits || '0'; end loop;
  for i in 0 .. length(v_bits) / 5 - 1 loop
    v_out := v_out || substr(v_alphabet, ('b' || substr(v_bits, i * 5 + 1, 5))::bit(5)::int + 1, 1);
  end loop;
  return v_out;
end $$;

-- A random string from an alphabet (rejection-free: alphabets used here divide 256 evenly
-- or are short enough that the bias is negligible for one-time codes).
create function public.random_code(p_length int, p_alphabet text) returns text
language plpgsql volatile set search_path = '' as $$
declare
  v_bytes bytea := extensions.gen_random_bytes(p_length);
  v_out text := '';
  i int;
begin
  for i in 0 .. p_length - 1 loop
    v_out := v_out || substr(p_alphabet, get_byte(v_bytes, i) % length(p_alphabet) + 1, 1);
  end loop;
  return v_out;
end $$;

-- URL-safe token with 256 bits of randomness.
create function public.random_token() returns text
language sql volatile set search_path = '' as $$
  select translate(rtrim(encode(extensions.gen_random_bytes(32), 'base64'), '='), '+/', '-_');
$$;

-- Fixed-window rate limit. Returns true when the call is allowed (and counts it).
create function public.take_rate_limit(p_key text, p_limit int, p_window interval, p_now timestamptz default now())
returns boolean
language plpgsql set search_path = '' as $$
declare
  v_start timestamptz := to_timestamp(floor(extract(epoch from p_now) / extract(epoch from p_window))
                                      * extract(epoch from p_window));
  v_count int;
begin
  insert into public.rate_limits (key, window_start, count) values (p_key, v_start, 1)
  on conflict (key, window_start) do update set count = public.rate_limits.count + 1
  returning count into v_count;
  return v_count <= p_limit;
end $$;

-- Unlock lengths (spec §6): 15, 30 or 60; premium any 15-minute step up to 240.
create function public.valid_unlock_length(p_minutes int, p_premium boolean) returns boolean
language sql immutable set search_path = '' as $$
  select p_minutes is not null and p_minutes between 15 and 240 and p_minutes % 15 = 0
     and (p_premium or p_minutes in (15, 30, 60));
$$;

-- ---------------------------------------------------------------------------
-- Premium (spec §12): one purchase covers the pair
-- ---------------------------------------------------------------------------

-- The user's own entitlement is active at p_now.
create function public.has_entitlement(p_user uuid, p_now timestamptz default now(), p_include_trial boolean default true)
returns boolean
language sql stable set search_path = '' as $$
  select exists (
    select 1 from public.entitlements
    where user_id = p_user and active and (expires_at is null or expires_at > p_now)
      and (p_include_trial or kind <> 'trial'));
$$;

-- Decide which member's purchase covers the pair and record it in pair_coverage.
--   * The current payer keeps covering while their entitlement is active.
--   * A trial covers a pair only if it is that pair's first trial (counted once per pair).
--   * A payer who started covering another pair less than 30 days ago cannot switch to
--     this one yet ("changing the covered partner: at most once per 30 days").
-- Returns the payer, or null when nobody covers the pair.
create function public.recompute_coverage(p_pair uuid, p_now timestamptz default now())
returns uuid
language plpgsql set search_path = '' as $$
declare
  v_pair public.pairs;
  v_current public.pair_coverage;
  v_payer uuid;
  m record;
  v_trial_ok boolean;
begin
  select * into v_pair from public.pairs where id = p_pair for update;
  if not found or v_pair.status <> 'active' then return null; end if;
  select * into v_current from public.pair_coverage where pair_id = p_pair;

  for m in
    select pm.user_id from public.pair_members pm
    where pm.pair_id = p_pair and pm.left_at is null
    -- The current payer first, so coverage does not flip between two paying partners.
    order by (pm.user_id = v_current.payer_id) desc nulls last, pm.joined_at, pm.user_id
  loop
    v_trial_ok := v_pair.trial_user_id is null or v_pair.trial_user_id = m.user_id;
    continue when not public.has_entitlement(m.user_id, p_now, v_trial_ok);
    -- Blocked if this person began covering a different pair within the last 30 days.
    continue when m.user_id is distinct from v_current.payer_id and exists (
      select 1 from public.pair_coverage c
      where c.payer_id = m.user_id and c.pair_id <> p_pair and c.covered_since > p_now - interval '30 days');
    v_payer := m.user_id;
    exit;
  end loop;

  if v_payer is null then
    delete from public.pair_coverage where pair_id = p_pair;
    return null;
  end if;

  -- Record the pair's one trial the first time a trial is what covers it.
  if v_pair.trial_user_id is null and not public.has_entitlement(v_payer, p_now, false) then
    update public.pairs set trial_user_id = v_payer, trial_started_at = p_now where id = p_pair;
  end if;

  insert into public.pair_coverage (pair_id, payer_id, covered_since, last_changed_at)
  values (p_pair, v_payer, p_now, p_now)
  on conflict (pair_id) do update
    set payer_id = excluded.payer_id,
        covered_since = case when public.pair_coverage.payer_id = excluded.payer_id
                             then public.pair_coverage.covered_since else excluded.covered_since end,
        last_changed_at = case when public.pair_coverage.payer_id = excluded.payer_id
                               then public.pair_coverage.last_changed_at else excluded.last_changed_at end;
  return v_payer;
end $$;

-- Premium for a person: covered through their active pair, or their own entitlement
-- (so the payer keeps premium after an unpair and the other partner does not).
create function public.is_premium(p_user uuid, p_now timestamptz default now()) returns boolean
language sql stable set search_path = '' as $$
  select public.has_entitlement(p_user, p_now)
      or exists (
        select 1 from public.pair_coverage c
        where c.pair_id = public.active_pair_of(p_user)
          and public.has_entitlement(c.payer_id, p_now));
$$;

-- Apply one RevenueCat event (WP-12 backend side). Older events than the newest applied
-- one for that product are ignored. Recomputes the payer's pair coverage.
create function public.api_apply_entitlement(
  p_user uuid, p_product text, p_kind public.entitlement_kind, p_active boolean,
  p_expires_at timestamptz, p_store public.store, p_event_at timestamptz,
  p_now timestamptz default now())
returns boolean
language plpgsql set search_path = '' as $$
declare
  v_pair uuid;
begin
  if not exists (select 1 from public.profiles where id = p_user) then perform public.fail('not_found'); end if;
  insert into public.entitlements (user_id, product_id, kind, active, expires_at, store, event_at, updated_at)
  values (p_user, p_product, p_kind, p_active, p_expires_at, p_store, p_event_at, p_now)
  on conflict (user_id, product_id) do update
    set kind = excluded.kind, active = excluded.active, expires_at = excluded.expires_at,
        store = excluded.store, event_at = excluded.event_at, updated_at = excluded.updated_at
    where public.entitlements.event_at is null or public.entitlements.event_at <= excluded.event_at;
  v_pair := public.active_pair_of(p_user);
  if v_pair is not null then perform public.recompute_coverage(v_pair, p_now); end if;
  return found;
end $$;

-- The caller's current pair, if its premium is on right now. Runs with the owner's rights
-- (so it can check the payer's entitlement) and shows only the caller's own pair.
create view public.pair_premium as
select c.pair_id, c.payer_id
from public.pair_coverage c
join public.pairs p on p.id = c.pair_id and p.status = 'active'
where public.is_pair_member(c.pair_id) and public.has_entitlement(c.payer_id);

-- ---------------------------------------------------------------------------
-- Pairing (spec §3)
-- ---------------------------------------------------------------------------
create function public.api_create_invite(p_user uuid, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  -- No 0/O, 1/I/L: the code is read aloud and typed.
  v_code text := public.random_code(6, 'ABCDEFGHJKMNPQRSTUVWXYZ23456789');
  v_token text := public.random_token();
  v_row public.invites;
begin
  if public.active_pair_of(p_user) is not null then perform public.fail('already_paired'); end if;
  update public.invites set revoked_at = p_now
    where inviter_id = p_user and accepted_at is null and revoked_at is null;
  insert into public.invites (inviter_id, code_hash, link_token_hash, expires_at, created_at)
  values (p_user, public.sha256_hex(v_code), public.sha256_hex(v_token), p_now + interval '72 hours', p_now)
  returning * into v_row;
  return jsonb_build_object('id', v_row.id, 'code', v_code, 'link_token', v_token, 'expires_at', v_row.expires_at);
end $$;

create function public.api_revoke_invite(p_user uuid, p_now timestamptz default now())
returns int
language plpgsql set search_path = '' as $$
declare v_count int;
begin
  update public.invites set revoked_at = p_now
    where inviter_id = p_user and accepted_at is null and revoked_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- Accept by the 6-character code or the link token. Creates the pair, both memberships,
-- the QR secret, each person's starting minutes and the coverage.
create function public.api_accept_invite(p_user uuid, p_code_or_token text, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_hash text := public.sha256_hex(case when length(p_code_or_token) = 6 then upper(p_code_or_token) else p_code_or_token end);
  v_invite public.invites;
  v_pair uuid;
  v_secret text := public.base32(extensions.gen_random_bytes(20));
  m uuid;
  v_start int;
begin
  select * into v_invite from public.invites
    where code_hash = v_hash or link_token_hash = v_hash
    for update;
  if not found or v_invite.revoked_at is not null or v_invite.inviter_id = p_user then
    perform public.fail('invalid');
  end if;
  if v_invite.accepted_at is not null then
    -- The same person tapping the link twice gets their pair back (idempotent).
    if v_invite.accepted_by = p_user and public.active_pair_of(p_user) is not null then
      return jsonb_build_object('pair_id', public.active_pair_of(p_user), 'partner_id', v_invite.inviter_id);
    end if;
    perform public.fail('invalid');
  end if;
  if v_invite.expires_at <= p_now then perform public.fail('expired'); end if;
  if public.active_pair_of(p_user) is not null or public.active_pair_of(v_invite.inviter_id) is not null then
    perform public.fail('already_paired');
  end if;

  insert into public.pairs (created_at) values (p_now) returning id into v_pair;
  insert into public.pair_members (pair_id, user_id, joined_at)
    values (v_pair, v_invite.inviter_id, p_now), (v_pair, p_user, p_now);
  insert into public.pair_secrets (pair_id, secret, version, updated_at) values (v_pair, v_secret, 1, p_now);
  insert into public.streaks (pair_id) values (v_pair);
  update public.invites set accepted_by = p_user, accepted_at = p_now where id = v_invite.id;

  foreach m in array array[v_invite.inviter_id, p_user] loop
    select starting_minutes into v_start from public.user_settings where user_id = m;
    if coalesce(v_start, 30) > 0 then
      perform public.grant_minutes(m, v_pair, coalesce(v_start, 30), 'starting_grant', 'pairs', v_pair, p_now);
    end if;
  end loop;
  perform public.recompute_coverage(v_pair, p_now);
  perform public.enqueue_notification(v_invite.inviter_id, 'paired',
    jsonb_build_object('pair_id', v_pair, 'from_user_id', p_user));
  return jsonb_build_object('pair_id', v_pair, 'partner_id', v_invite.inviter_id,
                            'qr_secret', v_secret, 'qr_secret_version', 1);
end $$;

-- Either partner, any time, no approval (spec §3). Minutes go to zero, pending items are
-- cancelled, history is kept, the other partner gets a neutral note.
create function public.api_unpair(p_user uuid, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pair uuid := public.active_pair_of(p_user);
  v_partner uuid := public.partner_of(p_user);
  m record;
begin
  if v_pair is null then perform public.fail('not_paired'); end if;
  perform 1 from public.pairs where id = v_pair for update;
  perform public.lock_minutes(variadic array[p_user, v_partner]);

  update public.pairs set status = 'ended', ended_at = p_now, ended_by = p_user where id = v_pair;
  update public.pair_members set left_at = p_now where pair_id = v_pair and left_at is null;
  for m in select user_id from public.pair_members where pair_id = v_pair order by user_id loop
    perform public.zero_balance(m.user_id, v_pair, 'pairs', v_pair, p_now);
  end loop;

  update public.unlock_requests set status = 'cancelled' where pair_id = v_pair and status = 'pending';
  update public.reset_proposals set status = 'expired' where pair_id = v_pair and status = 'pending';
  update public.schedule_change_requests set status = 'expired' where pair_id = v_pair and status = 'pending';
  update public.challenge_completions set status = 'expired'
    where pair_id = v_pair and status = 'awaiting_confirmation';
  delete from public.pair_secrets where pair_id = v_pair;
  -- The coverage row is kept: it is the record for the 30-day rule.

  perform public.enqueue_notification(v_partner, 'unpaired',
    jsonb_build_object('pair_id', v_pair, 'from_user_id', p_user));
  return jsonb_build_object('pair_id', v_pair);
end $$;

create function public.api_rotate_qr_secret(p_user uuid, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pair uuid := public.active_pair_of(p_user);
  v_secret text := public.base32(extensions.gen_random_bytes(20));
  v_version int;
begin
  if v_pair is null then perform public.fail('not_paired'); end if;
  update public.pair_secrets set secret = v_secret, version = version + 1, updated_at = p_now
    where pair_id = v_pair returning version into v_version;
  update public.pairs set qr_secret_version = v_version where id = v_pair;
  perform public.enqueue_notification(public.partner_of(p_user), 'qr_secret_rotated',
    jsonb_build_object('pair_id', v_pair, 'version', v_version));
  return jsonb_build_object('qr_secret', v_secret, 'qr_secret_version', v_version);
end $$;

-- ---------------------------------------------------------------------------
-- Unlocks (spec §6)
-- ---------------------------------------------------------------------------
create function public.new_unlock(
  p_user uuid, p_pair uuid, p_method public.unlock_method, p_minutes int, p_started_at timestamptz,
  p_request uuid default null, p_client_event_id uuid default null)
returns public.unlocks
language sql set search_path = '' as $$
  insert into public.unlocks (user_id, pair_id, method, minutes, started_at, ends_at, request_id, client_event_id)
  values (p_user, p_pair, p_method, p_minutes, p_started_at, p_started_at + make_interval(mins => p_minutes),
          p_request, p_client_event_id)
  returning *;
$$;

-- Ask your partner (§6.2). Valid 5 minutes; at most 3 per hour; push now, email fallback
-- after 2 minutes (at once if the partner has no push token).
create function public.api_create_unlock_request(
  p_user uuid, p_minutes int, p_reason text default null, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pair uuid := public.active_pair_of(p_user);
  v_partner uuid := public.partner_of(p_user);
  v_row public.unlock_requests;
  v_has_push boolean;
begin
  if v_pair is null or v_partner is null then perform public.fail('partner_missing'); end if;
  if not public.valid_unlock_length(p_minutes, public.is_premium(p_user, p_now)) then
    perform public.fail('invalid_input');
  end if;
  if char_length(p_reason) > 140 then perform public.fail('invalid_input'); end if;
  if (select count(*) from public.unlock_requests
      where requester_id = p_user and created_at > p_now - interval '1 hour') >= 3 then
    perform public.fail('rate_limited');
  end if;

  insert into public.unlock_requests (pair_id, requester_id, minutes, reason, expires_at, created_at)
  values (v_pair, p_user, p_minutes, nullif(btrim(p_reason), ''), p_now + interval '5 minutes', p_now)
  returning * into v_row;

  perform public.enqueue_notification(v_partner, 'unlock_request',
    jsonb_build_object('request_id', v_row.id, 'from_user_id', p_user, 'minutes', p_minutes, 'reason', v_row.reason));
  select exists (select 1 from public.push_tokens where user_id = v_partner) into v_has_push;
  perform public.enqueue_notification(v_partner, 'unlock_request_email',
    jsonb_build_object('request_id', v_row.id), 'email',
    case when v_has_push then p_now + interval '2 minutes' else p_now end);
  return to_jsonb(v_row) - 'code_hash' - 'approve_token_hash';
end $$;

-- Called by the email sender just before it sends the fallback email. Issues the 6-digit
-- accountability code and the approve-link token for a still-pending request; returns
-- null when the email is no longer needed (answered, expired or cancelled).
create function public.issue_unlock_email_secrets(p_request uuid, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row public.unlock_requests;
  v_code text := public.random_code(6, '0123456789');
  v_token text := public.random_token();
begin
  select * into v_row from public.unlock_requests where id = p_request for update;
  if not found or v_row.status <> 'pending' or v_row.expires_at <= p_now or v_row.email_sent_at is not null then
    return null;
  end if;
  update public.unlock_requests
    set code_hash = public.sha256_hex(v_code), approve_token_hash = public.sha256_hex(v_token), email_sent_at = p_now
    where id = p_request;
  return jsonb_build_object('code', v_code, 'approve_token', v_token, 'minutes', v_row.minutes,
                            'reason', v_row.reason, 'requester_id', v_row.requester_id, 'expires_at', v_row.expires_at);
end $$;

-- Mark a pending request expired if its time is up. Returns true if it is (now) expired.
create function public.expire_unlock_request_if_due(p_row public.unlock_requests, p_now timestamptz)
returns boolean
language plpgsql set search_path = '' as $$
begin
  if p_row.status = 'pending' and p_row.expires_at <= p_now then
    update public.unlock_requests set status = 'expired' where id = p_row.id;
    perform public.enqueue_notification(p_row.requester_id, 'unlock_expired', jsonb_build_object('request_id', p_row.id));
    return true;
  end if;
  return p_row.status = 'expired';
end $$;

-- Go for it / Let's wait. Errors are returned (not raised) when a status change must persist.
create function public.api_respond_unlock_request(
  p_user uuid, p_request uuid, p_approve boolean, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row public.unlock_requests;
  v_unlock public.unlocks;
begin
  select * into v_row from public.unlock_requests where id = p_request for update;
  if not found then perform public.fail('not_found'); end if;
  if v_row.requester_id = p_user or public.active_pair_of(p_user) is distinct from v_row.pair_id then
    perform public.fail('not_partner');
  end if;
  if public.expire_unlock_request_if_due(v_row, p_now) then
    return jsonb_build_object('error', 'expired');
  end if;
  if v_row.status <> 'pending' then
    if v_row.responded_by = p_user and (v_row.status = 'approved') = p_approve then
      return jsonb_build_object('request', to_jsonb(v_row) - 'code_hash' - 'approve_token_hash');
    end if;
    perform public.fail('already_responded');
  end if;

  update public.unlock_requests
    set status = case when p_approve then 'approved' else 'declined' end::public.unlock_request_status,
        responded_by = p_user, responded_at = p_now
    where id = p_request returning * into v_row;
  if p_approve then
    v_unlock := public.new_unlock(v_row.requester_id, v_row.pair_id, 'partner_approval', v_row.minutes, p_now, v_row.id);
  end if;
  perform public.enqueue_notification(v_row.requester_id,
    case when p_approve then 'unlock_approved' else 'unlock_declined' end,
    jsonb_build_object('request_id', v_row.id, 'from_user_id', p_user, 'unlock_id', v_unlock.id,
                       'minutes', v_row.minutes));
  return jsonb_build_object('request', to_jsonb(v_row) - 'code_hash' - 'approve_token_hash',
                            'unlock', case when v_unlock.id is null then null else to_jsonb(v_unlock) end);
end $$;

-- The requester types the 6-digit code their partner shared. Single use, 5 attempts.
create function public.api_redeem_accountability_code(
  p_user uuid, p_request uuid, p_code text, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row public.unlock_requests;
  v_unlock public.unlocks;
begin
  select * into v_row from public.unlock_requests where id = p_request for update;
  if not found or v_row.requester_id <> p_user then perform public.fail('not_found'); end if;
  if public.expire_unlock_request_if_due(v_row, p_now) then
    return jsonb_build_object('error', 'expired');
  end if;
  if v_row.status <> 'pending' or v_row.code_hash is null then perform public.fail('invalid'); end if;
  if v_row.code_attempts >= 5 then perform public.fail('too_many_attempts'); end if;
  if public.sha256_hex(btrim(coalesce(p_code, ''))) <> v_row.code_hash then
    update public.unlock_requests set code_attempts = code_attempts + 1 where id = p_request
      returning * into v_row;
    return jsonb_build_object('error', case when v_row.code_attempts >= 5 then 'too_many_attempts' else 'invalid' end);
  end if;

  update public.unlock_requests set status = 'redeemed', responded_at = p_now where id = p_request;
  v_unlock := public.new_unlock(p_user, v_row.pair_id, 'accountability_code', v_row.minutes, p_now, v_row.id);
  return jsonb_build_object('unlock', to_jsonb(v_unlock));
end $$;

-- Spend minutes on an unlock (§6.3). Idempotent by client_event_id.
create function public.api_spend_minutes_unlock(
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
  v_unlock := public.new_unlock(p_user, v_pair, 'minutes', p_minutes, p_now, null, p_client_event_id);
  perform public.spend_minutes(p_user, v_pair, p_minutes, v_unlock.id, p_now);
  return jsonb_build_object('unlock', to_jsonb(v_unlock), 'balance', public.balance_of(p_user, p_now));
end $$;

-- Emergency (§6.4): always available, 15 minutes, once per rolling 7 days, may borrow.
create function public.api_emergency_unlock(
  p_user uuid, p_client_event_id uuid, p_now timestamptz default now())
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
  if exists (select 1 from public.unlocks
             where user_id = p_user and method = 'emergency' and started_at > p_now - interval '7 days') then
    perform public.fail('used_this_week');
  end if;
  v_unlock := public.new_unlock(p_user, v_pair, 'emergency', 15, p_now, null, p_client_event_id);
  perform public.borrow_minutes(p_user, v_pair, 15, v_unlock.id, p_now);
  if v_pair is not null then
    perform public.mark_streak_break(v_pair, public.local_day(p_user, p_now), 'emergency');
    perform public.enqueue_notification(public.partner_of(p_user), 'emergency_used',
      jsonb_build_object('pair_id', v_pair, 'from_user_id', p_user));
  end if;
  return jsonb_build_object('unlock', to_jsonb(v_unlock), 'balance', public.balance_of(p_user, p_now));
end $$;

-- Offline QR unlocks recorded on the phone, synced later (§6.1). Each item:
-- {counter, minutes, started_at, client_event_id}. Idempotent per client_event_id; a
-- counter already used in the pair is rejected; the counter must match started_at
-- (30-second TOTP steps, ±3 steps) so a phone cannot invent unlocks for other times.
-- Returns one result per item: {client_event_id, status: recorded|duplicate|duplicate_counter|invalid}.
create function public.api_sync_qr_unlocks(p_user uuid, p_items jsonb, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pair uuid := public.active_pair_of(p_user);
  v_item jsonb;
  v_event uuid;
  v_counter bigint;
  v_minutes int;
  v_started timestamptz;
  v_unlock public.unlocks;
  v_results jsonb := '[]'::jsonb;
  v_status text;
begin
  if v_pair is null then perform public.fail('not_paired'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 50 then perform public.fail('invalid_input'); end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_status := null;
    begin
      v_event := (v_item ->> 'client_event_id')::uuid;
      v_counter := (v_item ->> 'counter')::bigint;
      v_minutes := (v_item ->> 'minutes')::int;
      v_started := (v_item ->> 'started_at')::timestamptz;
    exception when others then
      v_status := 'invalid';
    end;
    if v_status is null and (v_event is null or v_counter is null or v_started is null) then v_status := 'invalid'; end if;
    if v_status is null and exists (select 1 from public.unlocks where client_event_id = v_event) then
      v_status := 'duplicate';
    end if;
    if v_status is null and (
         not public.valid_unlock_length(v_minutes, true)
         or v_started > p_now + interval '5 minutes'
         or v_started < p_now - interval '30 days'
         or abs(v_counter - floor(extract(epoch from v_started) / 30)) > 3) then
      v_status := 'invalid';
    end if;
    if v_status is null and exists (select 1 from public.qr_redemptions where pair_id = v_pair and counter = v_counter) then
      v_status := 'duplicate_counter';
    end if;
    if v_status is null then
      v_unlock := public.new_unlock(p_user, v_pair, 'qr', v_minutes, v_started, null, v_event);
      insert into public.qr_redemptions (pair_id, user_id, counter, redeemed_at, unlock_id)
      values (v_pair, p_user, v_counter, v_started, v_unlock.id);
      v_status := 'recorded';
    end if;
    v_results := v_results || jsonb_build_object('client_event_id', v_item ->> 'client_event_id', 'status', v_status);
  end loop;
  return v_results;
end $$;

-- ---------------------------------------------------------------------------
-- Clients may read their current pair's QR secret (E14)
-- ---------------------------------------------------------------------------
grant select on public.pair_secrets to authenticated;
create policy pair_secrets_select_current on public.pair_secrets
  for select to authenticated using (public.is_pair_member(pair_id));
grant select on public.pair_premium to authenticated;
