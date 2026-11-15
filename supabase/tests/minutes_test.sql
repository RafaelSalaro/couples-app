-- The minutes engine: docs/03 §7, docs/07 §3 "Minutes".
begin;
\ir _helpers.psql
select plan(29);

-- Rafa (New York, UTC−5 in November) and Ana, paired.
create temp table t as
select tests.person('Rafa') as rafa, tests.person('Ana') as ana;
alter table t add column pair uuid;
update t set pair = tests.pair(rafa, ana, tests.at('2026-11-01 12:00'));

-- ---------------------------------------------------------------------------
-- Lots expire exactly 7 days later; spending takes the soonest-expiring lot first
-- ---------------------------------------------------------------------------
select public.grant_minutes(rafa, pair, 20, 'earn_challenge', null, null, tests.at('2026-11-02 10:00')) from t;
select public.grant_minutes(rafa, pair, 30, 'earn_kudos', null, null, tests.at('2026-11-03 10:00')) from t;

select is(
  (select expires_at from public.minute_lots where user_id = (select rafa from t) order by created_at limit 1),
  tests.at('2026-11-09 10:00'),
  'an earned lot expires exactly 7 days after it was earned');
select is(public.balance_of(rafa, tests.at('2026-11-04 12:00')), 50, 'balance is the sum of open lots') from t;

-- 30 minutes: all 20 of the older lot, then 10 of the newer one.
select public.spend_minutes(rafa, pair, 30, null, tests.at('2026-11-04 20:00')) from t;
select is(tests.lots(rafa), array['20'], 'spending emptied the soonest-expiring lot first and split the rest') from t;
select is(
  (select array_agg(minutes order by minutes) from public.minute_ledger
   where user_id = (select rafa from t) and type = 'spend_unlock'),
  array[-20, -10],
  'a spend across two lots writes one ledger row per lot');
select is(
  (select count(distinct lot_id)::int from public.minute_ledger
   where user_id = (select rafa from t) and type = 'spend_unlock'),
  2, 'each spend row points at the lot it came from');

-- ---------------------------------------------------------------------------
-- Expiry: the hourly job closes what is past its time and writes an 'expire' row
-- ---------------------------------------------------------------------------
select is(public.balance_of(rafa, tests.at('2026-11-10 10:01')), 0,
  'minutes past expires_at no longer count, even before the job runs') from t;
select is(public.expire_minutes(tests.at('2026-11-10 10:01')), 1, 'the expiry job closes one lot');
select is(
  (select minutes from public.minute_ledger where user_id = (select rafa from t) and type = 'expire'),
  -20, 'the expire row carries what was left in the lot');
select is(public.expire_minutes(tests.at('2026-11-10 11:01')), 0, 'running the expiry job again changes nothing');

-- ---------------------------------------------------------------------------
-- Daily maximum uses the user's local day (UTC−5: 11:30 PM and 12:30 AM)
-- ---------------------------------------------------------------------------
select public.grant_minutes(rafa, pair, 60, 'earn_challenge', null, null, tests.at('2026-11-12 09:00')) from t;
select public.grant_minutes(rafa, pair, 60, 'earn_challenge', null, null, tests.at('2026-11-12 09:00')) from t;
-- default daily maximum is 60
select lives_ok(
  format($q$select public.spend_minutes(%L, %L, 45, null, %L)$q$, rafa, pair, tests.at('2026-11-12 23:30')),
  '45 minutes at 11:30 PM local') from t;
select throws_ok(
  format($q$select public.spend_minutes(%L, %L, 30, null, %L)$q$, rafa, pair, tests.at('2026-11-12 23:45')),
  'CAERR', 'over_daily_max', 'another 30 the same local evening would pass the daily maximum') from t;
-- 11:45 PM and 12:30 AM local are both on 13 November in UTC: only the local day decides.
select lives_ok(
  format($q$select public.spend_minutes(%L, %L, 30, null, %L)$q$, rafa, pair, tests.at('2026-11-13 00:30')),
  '30 minutes at 12:30 AM local counts toward the next local day') from t;
select is(public.spent_today(rafa, tests.at('2026-11-13 00:31')), 30, 'the new local day has 30 spent') from t;
select is(
  (select array_agg(distinct local_day order by local_day) from public.minute_ledger
   where user_id = (select rafa from t) and type = 'spend_unlock' and created_at >= tests.at('2026-11-12 00:00')),
  array['2026-11-12'::date, '2026-11-13'::date], 'ledger rows record the local day');

select throws_ok(
  format($q$select public.spend_minutes(%L, %L, 60, null, %L)$q$, rafa, pair, tests.at('2026-11-13 01:00')),
  'CAERR', 'insufficient', 'spending more than the balance is refused') from t;
select throws_ok(
  format($q$select public.spend_minutes(%L, %L, 0, null, %L)$q$, rafa, pair, tests.at('2026-11-13 01:00')),
  'CAERR', 'invalid_input', 'spending zero is refused') from t;

-- ---------------------------------------------------------------------------
-- Debt from an emergency unlock is repaid first; no spending while in debt
-- ---------------------------------------------------------------------------
-- Ana has nothing and borrows 15.
select public.borrow_minutes(ana, pair, 15, null, tests.at('2026-11-12 22:00')) from t;
select is(public.balance_of(ana, tests.at('2026-11-12 22:01')), -15, 'an emergency borrow can take the balance negative') from t;
select is((select debt from public.minute_debt where user_id = (select ana from t)), 15, 'the shortfall is recorded as debt');
select throws_ok(
  format($q$select public.spend_minutes(%L, %L, 15, null, %L)$q$, ana, pair, tests.at('2026-11-12 22:05')),
  'CAERR', 'in_debt', 'spending is refused while in debt') from t;
select is(public.grant_minutes(ana, pair, 10, 'earn_kudos', null, null, tests.at('2026-11-12 22:10')), null::uuid,
  'a credit smaller than the debt creates no lot') from t;
select is((select debt from public.minute_debt where user_id = (select ana from t)), 5, 'it repaid 10 of the debt');
select isnt(public.grant_minutes(ana, pair, 20, 'earn_challenge', null, null, tests.at('2026-11-12 22:20')), null::uuid,
  'a larger credit repays the rest and keeps the remainder') from t;
select is(tests.lots(ana), array['15'], 'only what is left after repaying becomes a lot') from t;
select is(
  (select sum(minutes)::int from public.minute_ledger where user_id = (select ana from t) and type = 'debt_repay'),
  15, 'repayments are ledger rows');

-- ---------------------------------------------------------------------------
-- Mutual reset: both must agree; everything is expired first, then the standard grant
-- ---------------------------------------------------------------------------
create temp table r as
select (public.api_propose_reset(rafa, null, tests.at('2026-11-13 08:00')) ->> 'id')::uuid as id from t;
select throws_ok(
  format($q$select public.api_respond_reset(%L, %L, true, %L)$q$, (select rafa from t), id, tests.at('2026-11-13 08:01')),
  'CAERR', 'not_partner', 'the proposer cannot accept their own reset') from r;
select is(public.balance_of(rafa, tests.at('2026-11-13 08:02')), 45, 'nothing changes until the partner accepts') from t;
select public.api_respond_reset((select ana from t), id, true, tests.at('2026-11-13 09:00')) from r;
select ok(
  public.balance_of(rafa, tests.at('2026-11-13 09:01')) = 30 and public.balance_of(ana, tests.at('2026-11-13 09:01')) = 30,
  'after both agree, both balances are the standard 30') from t;
select is(
  (select count(*)::int from public.minute_lots
   where user_id in ((select rafa from t), (select ana from t)) and closed_at is null),
  2, 'every earlier lot was closed: each now has only the new grant');

-- ---------------------------------------------------------------------------
-- The ledger is immutable and clients cannot call the engine
-- ---------------------------------------------------------------------------
select throws_ok(
  $q$update public.minute_ledger set minutes = 999$q$,
  '42501', null, 'the ledger cannot be edited, not even by the owner role');

select * from finish();
rollback;
