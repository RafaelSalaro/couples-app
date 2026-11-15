-- Unlocks: docs/03 §6, docs/07 §3 "Unlocks".
begin;
\ir _helpers.psql
select plan(29);

create temp table t as select tests.person('Rafa') as rafa, tests.person('Ana') as ana;
alter table t add column pair uuid;
update t set pair = tests.pair(rafa, ana, tests.at('2026-11-01 12:00'));

-- ---------------------------------------------------------------------------
-- Ask your partner: valid 5 minutes; approval after expiry fails
-- ---------------------------------------------------------------------------
create temp table req as
select (public.api_create_unlock_request(rafa, 30, 'Reply to a client', tests.at('2026-11-10 20:00')) ->> 'id')::uuid as id from t;
select is((select expires_at from public.unlock_requests where id = (select id from req)),
  tests.at('2026-11-10 20:05'), 'a request is valid for 5 minutes');
select is((select code_hash from public.unlock_request_secrets where request_id = (select id from req)), null,
  'no accountability code exists until the email fallback is sent');
select is((select count(*)::int from public.notifications_outbox where kind = 'unlock_request' and user_id = (select ana from t)),
  1, 'the partner gets a push');
select is((select send_after from public.notifications_outbox where kind = 'unlock_request_email'),
  tests.at('2026-11-10 20:00'), 'with no push token the email fallback goes at once');

select throws_ok(
  format($q$select public.api_respond_unlock_request(%L, %L, true, %L)$q$, (select rafa from t), id, tests.at('2026-11-10 20:01')),
  'CAERR', 'not_partner', 'the requester cannot approve their own request') from req;
select is(public.api_respond_unlock_request((select ana from t), id, true, tests.at('2026-11-10 20:05')) ->> 'error',
  'expired', 'approving at 5 minutes fails: the request has expired') from req;
select is((select status::text from public.unlock_requests where id = (select id from req)), 'expired',
  'the request is marked expired');
select is((select count(*)::int from public.unlocks), 0, 'no unlock was created');

-- In time: Go for it creates the unlock for the requester.
insert into public.push_tokens (user_id, platform, token) select ana, 'ios', 'token-ana-0001' from t;
create temp table req2 as
select (public.api_create_unlock_request(rafa, 30, null, tests.at('2026-11-10 21:00')) ->> 'id')::uuid as id from t;
select is((select send_after from public.notifications_outbox where kind = 'unlock_request_email'
           and payload ->> 'request_id' = (select id from req2)::text),
  tests.at('2026-11-10 21:02'), 'when the partner has push, the email fallback waits 2 minutes');
select is(public.api_respond_unlock_request((select ana from t), id, true, tests.at('2026-11-10 21:01')) -> 'unlock' ->> 'minutes',
  '30', 'Go for it within 5 minutes starts a 30-minute unlock') from req2;
select is(public.api_respond_unlock_request((select ana from t), id, true, tests.at('2026-11-10 21:02')) -> 'request' ->> 'status',
  'approved', 'answering the same way twice is idempotent') from req2;
select throws_ok(
  format($q$select public.api_respond_unlock_request(%L, %L, false, %L)$q$, (select ana from t), id, tests.at('2026-11-10 21:02')),
  'CAERR', 'already_responded', 'changing the answer afterwards is refused') from req2;

-- 3 requests per hour: 21:00 (above), 21:10 and 21:20 are fine, a fourth at 21:30 is not.
select public.api_create_unlock_request(rafa, 15, null, tests.at('2026-11-10 21:10')) from t;
select public.api_create_unlock_request(rafa, 15, null, tests.at('2026-11-10 21:20')) from t;
select throws_ok(
  format($q$select public.api_create_unlock_request(%L, 15, null, %L)$q$, rafa, tests.at('2026-11-10 21:30')),
  'CAERR', 'rate_limited', 'a fourth request within the hour is refused') from t;
select throws_ok(
  format($q$select public.api_create_unlock_request(%L, 45, null, %L)$q$, ana, tests.at('2026-11-10 21:30')),
  'CAERR', 'invalid_input', '45 minutes is a premium length') from t;

-- ---------------------------------------------------------------------------
-- Accountability code: hashed at rest, 5 attempts, single use
-- ---------------------------------------------------------------------------
create temp table req3 as
select (public.api_create_unlock_request(ana, 15, null, tests.at('2026-11-11 20:00')) ->> 'id')::uuid as id from t;
create temp table code as
select public.issue_unlock_email_secrets(id, tests.at('2026-11-11 20:02')) ->> 'code' as code from req3;
select matches((select code from code), '^[0-9]{6}$', 'the email carries a 6-digit code');
select is((select code_hash from public.unlock_request_secrets where request_id = (select id from req3)),
  public.sha256_hex((select code from code)), 'only its hash is stored');
select is(public.issue_unlock_email_secrets((select id from req3), tests.at('2026-11-11 20:03')), null,
  'the code is issued once');

select is(public.api_redeem_accountability_code((select ana from t), (select id from req3), '000000', tests.at('2026-11-11 20:03')) ->> 'error',
  'invalid', 'a wrong code counts an attempt')
  where (select code from code) <> '000000';
select is((select code_attempts from public.unlock_requests where id = (select id from req3)), 1, 'the attempt is recorded');
select is(public.api_redeem_accountability_code((select ana from t), (select id from req3), (select code from code), tests.at('2026-11-11 20:04')) -> 'unlock' ->> 'method',
  'accountability_code', 'the right code unlocks');
select throws_ok(
  format($q$select public.api_redeem_accountability_code(%L, %L, %L, %L)$q$,
         (select ana from t), (select id from req3), (select code from code), tests.at('2026-11-11 20:04')),
  'CAERR', 'invalid', 'the code works only once');

-- Five wrong tries end it.
create temp table req4 as
select (public.api_create_unlock_request(ana, 15, null, tests.at('2026-11-12 20:00')) ->> 'id')::uuid as id from t;
select public.issue_unlock_email_secrets(id, tests.at('2026-11-12 20:01')) from req4;
select public.api_redeem_accountability_code((select ana from t), id, 'nope', tests.at('2026-11-12 20:02'))
  from req4, generate_series(1, 5);
select throws_ok(
  format($q$select public.api_redeem_accountability_code(%L, %L, 'nope', %L)$q$, (select ana from t), id, tests.at('2026-11-12 20:03')),
  'CAERR', 'too_many_attempts', 'after 5 attempts no more are allowed') from req4;

-- ---------------------------------------------------------------------------
-- Offline QR sync: idempotent; a reused counter is rejected
-- ---------------------------------------------------------------------------
create temp table qr as
select gen_random_uuid() as e1, gen_random_uuid() as e2,
       floor(extract(epoch from tests.at('2026-11-12 21:00')) / 30)::bigint as counter;
select is(
  public.api_sync_qr_unlocks((select rafa from t), jsonb_build_array(jsonb_build_object(
    'client_event_id', e1, 'counter', counter, 'minutes', 30, 'started_at', tests.at('2026-11-12 21:00'))),
    tests.at('2026-11-12 23:00')) -> 0 ->> 'status',
  'recorded', 'an offline QR unlock is recorded') from qr;
select is(
  public.api_sync_qr_unlocks((select rafa from t), jsonb_build_array(jsonb_build_object(
    'client_event_id', e1, 'counter', counter, 'minutes', 30, 'started_at', tests.at('2026-11-12 21:00'))),
    tests.at('2026-11-12 23:05')) -> 0 ->> 'status',
  'duplicate', 'syncing the same unlock again changes nothing') from qr;
select is(
  public.api_sync_qr_unlocks((select ana from t), jsonb_build_array(jsonb_build_object(
    'client_event_id', e2, 'counter', counter, 'minutes', 15, 'started_at', tests.at('2026-11-12 21:00'))),
    tests.at('2026-11-12 23:05')) -> 0 ->> 'status',
  'duplicate_counter', 'a code already used in the pair is rejected') from qr;
select is(
  public.api_sync_qr_unlocks((select ana from t), jsonb_build_array(jsonb_build_object(
    'client_event_id', gen_random_uuid(), 'counter', counter, 'minutes', 15, 'started_at', tests.at('2026-11-12 22:00'))),
    tests.at('2026-11-12 23:05')) -> 0 ->> 'status',
  'invalid', 'a counter that does not match the start time is rejected') from qr;

-- ---------------------------------------------------------------------------
-- Emergency unlock: once per rolling 7 days, may borrow
-- ---------------------------------------------------------------------------
select is(public.api_emergency_unlock(rafa, gen_random_uuid(), tests.at('2026-11-13 22:00')) ->> 'balance',
  '-15', 'an emergency unlock with no minutes borrows 15') from t;
select throws_ok(
  format($q$select public.api_emergency_unlock(%L, %L, %L)$q$, rafa, gen_random_uuid(), tests.at('2026-11-20 21:59')),
  'CAERR', 'used_this_week', 'a second one within 7 days is refused') from t;
select lives_ok(
  format($q$select public.api_emergency_unlock(%L, %L, %L)$q$, rafa, gen_random_uuid(), tests.at('2026-11-20 22:01')),
  'after 7 days it is available again') from t;

select * from finish();
rollback;
