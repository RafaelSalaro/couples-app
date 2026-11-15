-- Fixes from the backend security review (docs/security-review-backend.md).

-- ---------------------------------------------------------------------------
-- R1. Unlock request secrets move to a server-only table.
-- The hashes were kept from clients with column-level grants, which made the app's
-- `select *` on unlock_requests fail (PostgREST asks for every column). With the secrets in
-- their own table, members may read the whole request row.
-- ---------------------------------------------------------------------------
create table public.unlock_request_secrets (
  request_id uuid primary key references public.unlock_requests (id) on delete cascade,
  code_hash text,
  approve_token_hash text
);
alter table public.unlock_request_secrets enable row level security;
revoke all on public.unlock_request_secrets from anon, authenticated;
grant all on public.unlock_request_secrets to service_role;
create unique index unlock_request_secrets_token on public.unlock_request_secrets (approve_token_hash)
  where approve_token_hash is not null;

insert into public.unlock_request_secrets (request_id, code_hash, approve_token_hash)
select id, code_hash, approve_token_hash from public.unlock_requests
where code_hash is not null or approve_token_hash is not null;

alter table public.unlock_requests drop column code_hash, drop column approve_token_hash;
grant select on public.unlock_requests to authenticated;

create or replace function public.issue_unlock_email_secrets(p_request uuid, p_now timestamptz default now())
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
  insert into public.unlock_request_secrets (request_id, code_hash, approve_token_hash)
  values (p_request, public.sha256_hex(v_code), public.sha256_hex(v_token))
  on conflict (request_id) do update set code_hash = excluded.code_hash, approve_token_hash = excluded.approve_token_hash;
  update public.unlock_requests set email_sent_at = p_now where id = p_request;
  return jsonb_build_object('code', v_code, 'approve_token', v_token, 'minutes', v_row.minutes,
                            'reason', v_row.reason, 'requester_id', v_row.requester_id, 'expires_at', v_row.expires_at);
end $$;

create or replace function public.api_redeem_accountability_code(
  p_user uuid, p_request uuid, p_code text, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row public.unlock_requests;
  v_hash text;
  v_unlock public.unlocks;
begin
  select * into v_row from public.unlock_requests where id = p_request for update;
  if not found or v_row.requester_id <> p_user then perform public.fail('not_found'); end if;
  if public.expire_unlock_request_if_due(v_row, p_now) then
    return jsonb_build_object('error', 'expired');
  end if;
  select code_hash into v_hash from public.unlock_request_secrets where request_id = p_request;
  if v_row.status <> 'pending' or v_hash is null then perform public.fail('invalid'); end if;
  if v_row.code_attempts >= 5 then perform public.fail('too_many_attempts'); end if;
  if public.sha256_hex(btrim(coalesce(p_code, ''))) <> v_hash then
    update public.unlock_requests set code_attempts = code_attempts + 1 where id = p_request
      returning * into v_row;
    return jsonb_build_object('error', case when v_row.code_attempts >= 5 then 'too_many_attempts' else 'invalid' end);
  end if;

  update public.unlock_requests set status = 'redeemed', responded_at = p_now where id = p_request;
  v_unlock := public.new_unlock(p_user, v_row.pair_id, 'accountability_code', v_row.minutes, p_now, v_row.id);
  return jsonb_build_object('unlock', to_jsonb(v_unlock));
end $$;

create or replace function public.api_respond_unlock_by_token(p_token text, p_approve boolean, p_now timestamptz default now())
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row public.unlock_requests;
  v_partner uuid;
begin
  select r.* into v_row from public.unlock_requests r
    join public.unlock_request_secrets s on s.request_id = r.id
    where s.approve_token_hash = public.sha256_hex(coalesce(p_token, ''));
  if not found then perform public.fail('invalid'); end if;
  select user_id into v_partner from public.pair_members
    where pair_id = v_row.pair_id and user_id <> v_row.requester_id and left_at is null;
  if v_partner is null then perform public.fail('invalid'); end if;
  return public.api_respond_unlock_request(v_partner, v_row.id, p_approve, p_now);
end $$;

-- ---------------------------------------------------------------------------
-- R2. Accepting an invite is rate limited: 10 tries per person per hour.
-- Without a limit, someone could try codes until one matched a stranger's open invite
-- (6 characters from 31, about 887 million codes, many open at once). Failed tries are
-- returned, not raised, so the count persists.
-- ---------------------------------------------------------------------------
create or replace function public.api_accept_invite(p_user uuid, p_code_or_token text, p_now timestamptz default now())
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
  if not public.take_rate_limit('accept_invite:' || p_user::text, 10, interval '1 hour', p_now) then
    return jsonb_build_object('error', 'rate_limited');
  end if;
  select * into v_invite from public.invites
    where code_hash = v_hash or link_token_hash = v_hash
    for update;
  if not found or v_invite.revoked_at is not null or v_invite.inviter_id = p_user then
    return jsonb_build_object('error', 'invalid');
  end if;
  if v_invite.accepted_at is not null then
    -- The same person tapping the link twice gets their pair back (idempotent).
    if v_invite.accepted_by = p_user and public.active_pair_of(p_user) is not null then
      return jsonb_build_object('pair_id', public.active_pair_of(p_user), 'partner_id', v_invite.inviter_id);
    end if;
    return jsonb_build_object('error', 'invalid');
  end if;
  if v_invite.expires_at <= p_now then return jsonb_build_object('error', 'expired'); end if;
  if public.active_pair_of(p_user) is not null or public.active_pair_of(v_invite.inviter_id) is not null then
    return jsonb_build_object('error', 'already_paired');
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

-- ---------------------------------------------------------------------------
-- R3. "Protected time is off" is reported by the phone, as doc 05 intends, and the partner
-- is told (spec §11). The app could not write this column (403). The server stamps the time
-- itself, so a phone cannot back- or post-date it, queues the neutral note to the partner,
-- and marks the day as breaking the shared streak (spec §9).
-- ---------------------------------------------------------------------------
grant update (protected_time_off_since) on public.profiles to authenticated;

create function public.protected_time_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_partner uuid := public.partner_of(new.id);
  v_pair uuid := public.active_pair_of(new.id);
begin
  if (old.protected_time_off_since is null) = (new.protected_time_off_since is null) then
    new.protected_time_off_since := old.protected_time_off_since;  -- no change of state: keep the original time
    return new;
  end if;
  if new.protected_time_off_since is not null then
    new.protected_time_off_since := now();
    if v_pair is not null then
      perform public.mark_streak_break(v_pair, public.local_day(new.id), 'protected_time_off');
    end if;
  end if;
  perform public.enqueue_notification(v_partner,
    case when new.protected_time_off_since is null then 'protected_time_on' else 'protected_time_off' end,
    jsonb_build_object('from_user_id', new.id, 'pair_id', v_pair));
  return new;
end $$;
revoke execute on function public.protected_time_changed() from public, anon, authenticated;
create trigger profiles_protected_time_changed before update of protected_time_off_since on public.profiles
  for each row execute function public.protected_time_changed();

-- ---------------------------------------------------------------------------
-- R4. Registering a push token is an upsert that sets user_id on conflict; clients may now
-- update that column, still only to themselves (the policy's WITH CHECK). The app's call
-- failed with 403 before.
-- ---------------------------------------------------------------------------
grant update (user_id) on public.push_tokens to authenticated;

-- ---------------------------------------------------------------------------
-- R5. Smaller hardening
-- ---------------------------------------------------------------------------

-- Kudos may point only at a challenge the pair can see (a preset or its own).
create function public.check_kudos_challenge() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.challenge_id is not null and not exists (
       select 1 from public.challenges c
       where c.id = new.challenge_id and (c.pair_id is null or c.pair_id = new.pair_id)) then
    perform public.fail('invalid_input');
  end if;
  return new;
end $$;
create trigger kudos_check_challenge before insert on public.kudos
  for each row execute function public.check_kudos_challenge();

-- A schedule proposal is small; refuse anything larger than 2 KB (it is stored and pushed).
alter table public.schedule_change_requests
  add constraint schedule_change_requests_proposed_size check (pg_column_size(proposed) <= 2048);

-- Rate-limit windows older than a day are no longer needed.
create function public.prune_rate_limits(p_now timestamptz default now()) returns int
language plpgsql set search_path = '' as $$
declare v_count int;
begin
  delete from public.rate_limits where window_start < p_now - interval '1 day';
  get diagnostics v_count = row_count;
  return v_count;
end $$;
select cron.schedule('prune_rate_limits', '40 3 * * *', $$select public.prune_rate_limits()$$);

-- Helper and trigger functions created before default execute rights were revoked could
-- still be executed by the anonymous role. Harmless (they need a signed-in user), but not
-- intended: only signed-in users, for the RLS helpers.
revoke execute on function public.is_pair_member(uuid), public.was_pair_member(uuid), public.is_partner(uuid)
  from public, anon;
grant execute on function public.is_pair_member(uuid), public.was_pair_member(uuid), public.is_partner(uuid)
  to authenticated, service_role;
revoke execute on function public.handle_new_user(), public.claim_push_token(), public.check_time_zone(),
  public.touch_updated_at(), public.forbid_ledger_update() from public, anon, authenticated;
