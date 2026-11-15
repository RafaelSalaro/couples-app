-- Edge cases for the minutes ledger, unlocks and time zones (docs/12 §6 "if credits remain",
-- item 1). The main cases live in minutes_test.sql and unlocks_test.sql.
begin;
\ir _helpers.psql
select plan(24);

-- The ledger must always explain the balance: for every person, the sum of their ledger rows
-- equals what they can spend minus what they owe.
create function tests.ledger_balanced(p_user uuid, p_at timestamptz) returns boolean language sql as $$
  select coalesce((select sum(minutes) from public.minute_ledger where user_id = p_user and created_at <= p_at), 0)
       = public.balance_of(p_user, p_at)
         + coalesce((select sum(remaining) from public.minute_lots
                     where user_id = p_user and closed_at is null and expires_at <= p_at), 0);
$$;

create temp table t as select tests.person('Rafa') as rafa, tests.person('Ana') as ana, tests.person('Bea') as bea;
alter table t add column pair uuid;
update t set pair = tests.pair(rafa, ana, tests.at('2026-10-01 12:00'));

-- ---------------------------------------------------------------------------
-- Expiry is exact to the instant
-- ---------------------------------------------------------------------------
select public.grant_minutes(rafa, pair, 20, 'earn_kudos', null, null, tests.at('2026-10-05 21:00')) from t;
select is(public.balance_of(rafa, tests.at('2026-10-12 20:59:59')), 20, 'a lot still counts one second before it expires') from t;
select is(public.balance_of(rafa, tests.at('2026-10-12 21:00')), 0, 'and not at its expiry instant') from t;
select throws_ok(
  format($q$select public.spend_minutes(%L, %L, 15, null, %L)$q$, rafa, pair, tests.at('2026-10-12 21:00')),
  'CAERR', 'insufficient', 'an expired lot cannot be spent even before the expiry job has run') from t;

-- ---------------------------------------------------------------------------
-- Daily maximum: exactly at the limit, a lowered limit, and the 25-hour fall-back day
-- ---------------------------------------------------------------------------
select public.grant_minutes(ana, pair, 60, 'earn_challenge', null, null, tests.at('2026-10-20 09:00')) from t;
select public.grant_minutes(ana, pair, 60, 'earn_challenge', null, null, tests.at('2026-10-20 09:00')) from t;
select lives_ok(format($q$select public.spend_minutes(%L, %L, 45, null, %L)$q$, ana, pair, tests.at('2026-10-20 20:00')),
  '45 of a 60-minute maximum') from t;
select lives_ok(format($q$select public.spend_minutes(%L, %L, 15, null, %L)$q$, ana, pair, tests.at('2026-10-20 21:00')),
  'exactly reaching the maximum is allowed') from t;
select throws_ok(format($q$select public.spend_minutes(%L, %L, 15, null, %L)$q$, ana, pair, tests.at('2026-10-20 21:30')),
  'CAERR', 'over_daily_max', 'one more unlock that day is not') from t;
update public.user_settings set daily_max_minutes = 30 where user_id = (select ana from t);
select is(public.spent_today(ana, tests.at('2026-10-20 22:00')), 60, 'lowering the maximum later in the day undoes nothing') from t;

-- 1 November 2026: clocks go back at 2:00 in New York, so the local day lasts 25 hours.
update public.user_settings set daily_max_minutes = 60 where user_id = (select ana from t);
select public.grant_minutes(ana, pair, 60, 'earn_challenge', null, null, tests.at('2026-10-31 12:00')) from t;
select public.grant_minutes(ana, pair, 60, 'earn_challenge', null, null, tests.at('2026-10-31 12:00')) from t;
select lives_ok(format($q$select public.spend_minutes(%L, %L, 45, null, %L)$q$, ana, pair, '2026-11-01 04:30+00'),
  '45 minutes at 00:30 on the fall-back day') from t;
select throws_ok(format($q$select public.spend_minutes(%L, %L, 30, null, %L)$q$, ana, pair, tests.at('2026-11-01 23:30')),
  'CAERR', 'over_daily_max', 'at 23:30 the same local day (25 hours later) the maximum still applies') from t;
select lives_ok(format($q$select public.spend_minutes(%L, %L, 15, null, %L)$q$, ana, pair, tests.at('2026-11-02 00:10')),
  'ten minutes after local midnight it is a new day') from t;

-- ---------------------------------------------------------------------------
-- Debt at its boundaries
-- ---------------------------------------------------------------------------
-- Bea is not paired: emergency unlocks and debt work without a partner.
select public.borrow_minutes(bea, null, 15, null, tests.at('2026-10-10 20:00')) from t;
select is(public.grant_minutes(bea, null, 15, 'earn_kudos', null, null, tests.at('2026-10-11 20:00')), null::uuid,
  'a credit exactly equal to the debt repays it and creates no lot') from t;
select ok(public.balance_of(bea, tests.at('2026-10-11 20:01')) = 0
          and (select debt from public.minute_debt where user_id = (select bea from t)) = 0,
  'leaving a balance of zero and no debt') from t;
select throws_ok(format($q$select public.spend_minutes(%L, null, 15, null, %L)$q$, bea, tests.at('2026-10-11 20:02')),
  'CAERR', 'insufficient', 'with nothing left the refusal is "insufficient", not "in debt"') from t;

-- A partial balance is used first; only the shortfall becomes debt.
select public.grant_minutes(bea, null, 10, 'earn_kudos', null, null, tests.at('2026-10-12 12:00')) from t;
select public.borrow_minutes(bea, null, 15, null, tests.at('2026-10-12 20:00')) from t;
select ok(public.balance_of(bea, tests.at('2026-10-12 20:01')) = -5
          and (select debt from public.minute_debt where user_id = (select bea from t)) = 5,
  'borrowing 15 with 10 in hand takes the 10 and owes 5') from t;
select ok(tests.ledger_balanced(bea, tests.at('2026-10-12 20:01')), 'the ledger explains Bea''s balance') from t;

-- ---------------------------------------------------------------------------
-- The ledger explains every balance after a long mixed history
-- ---------------------------------------------------------------------------
select public.borrow_minutes(rafa, pair, 15, null, tests.at('2026-10-21 20:00')) from t;
select public.grant_minutes(rafa, pair, 25, 'earn_challenge', null, null, tests.at('2026-10-22 20:00')) from t;
select public.expire_minutes(tests.at('2026-11-05 00:00'));
select public.grant_minutes(rafa, pair, 30, 'earn_kudos', null, null, tests.at('2026-11-06 12:00')) from t;
select public.spend_minutes(rafa, pair, 15, null, tests.at('2026-11-06 20:00')) from t;
select ok(tests.ledger_balanced(rafa, tests.at('2026-11-06 20:01')) and tests.ledger_balanced(ana, tests.at('2026-11-06 20:01')),
  'after earning, borrowing, repaying, expiring and spending, the ledger explains both balances') from t;

-- Unpairing forgives debt and empties lots; the ledger still balances at zero.
select public.borrow_minutes(ana, pair, 75, null, tests.at('2026-11-07 20:00')) from t; -- more than she has: some debt
select public.api_unpair(rafa, tests.at('2026-11-08 12:00')) from t;
select ok(public.balance_of(rafa, tests.at('2026-11-08 12:01')) = 0 and public.balance_of(ana, tests.at('2026-11-08 12:01')) = 0
          and (select coalesce(sum(debt), 0) from public.minute_debt where user_id in ((select rafa from t), (select ana from t))) = 0,
  'unpairing leaves both at zero with no debt') from t;
select ok(tests.ledger_balanced(rafa, tests.at('2026-11-08 12:01')) and tests.ledger_balanced(ana, tests.at('2026-11-08 12:01')),
  'and the ledger still explains it') from t;

-- ---------------------------------------------------------------------------
-- Unlocks: an expired request cannot be redeemed; QR counters are per pair
-- ---------------------------------------------------------------------------
create temp table p2 as select tests.pair((select rafa from t), (select bea from t), tests.at('2026-11-09 10:00')) as pair;
create temp table req as
select (public.api_create_unlock_request((select rafa from t), 15, null, tests.at('2026-11-09 20:00')) ->> 'id')::uuid as id;
create temp table code as select public.issue_unlock_email_secrets(id, tests.at('2026-11-09 20:02')) ->> 'code' as code from req;
select is(public.api_redeem_accountability_code((select rafa from t), (select id from req), (select code from code), tests.at('2026-11-09 20:05')) ->> 'error',
  'expired', 'the right code after the request expired does not unlock');
select is((select status::text from public.unlock_requests where id = (select id from req)), 'expired', 'the request stays expired');

-- The same TOTP counter used by an earlier pair is fine in a new pair (codes come from each pair's own secret).
insert into public.qr_redemptions (pair_id, user_id, counter, redeemed_at)
select pair, rafa, floor(extract(epoch from tests.at('2026-11-09 21:00')) / 30)::bigint, tests.at('2026-11-09 21:00') from t;
select is(
  public.api_sync_qr_unlocks((select rafa from t), jsonb_build_array(jsonb_build_object(
    'client_event_id', gen_random_uuid(), 'counter', floor(extract(epoch from tests.at('2026-11-09 21:00')) / 30)::bigint,
    'minutes', 15, 'started_at', tests.at('2026-11-09 21:00'))), tests.at('2026-11-09 22:00')) -> 0 ->> 'status',
  'recorded', 'a counter used in an earlier pair is accepted in the new pair');

-- ---------------------------------------------------------------------------
-- Schedules on the spring-forward day: a window starting in the skipped hour
-- ---------------------------------------------------------------------------
-- 8 March 2026: 2:00 → 3:00 in New York, so 02:30 does not exist that night.
select ok(public.schedule_protects(array[7]::smallint[], '02:30', '05:00', 'America/New_York', tests.at('2026-03-08 04:00')),
  'a window starting in the skipped hour still protects the rest of the night');
select ok(not public.schedule_protects(array[7]::smallint[], '02:30', '05:00', 'America/New_York', tests.at('2026-03-08 01:59')),
  'and does not start early');

-- Kudos cap follows the giver's local day.
select public.api_apply_entitlement(bea, 'lifetime', 'lifetime', true, null, 'app_store', tests.at('2026-11-09 10:00'), tests.at('2026-11-09 10:00')) from t;
select public.api_give_kudos(bea, 30, '', null, tests.at('2026-11-10 23:00')) from t;
select public.api_give_kudos(bea, 30, '', null, tests.at('2026-11-10 23:30')) from t;
select lives_ok(format($q$select public.api_give_kudos(%L, 10, '', null, %L)$q$, (select bea from t), tests.at('2026-11-11 00:05')),
  'after local midnight the giver can give kudos again');

select * from finish();
rollback;
