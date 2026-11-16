-- The weekly emergency allowance (P14) and ending unlocks early (P26): docs/03 §6 and §6.4,
-- docs/07 §3 "Minutes".
begin;
\ir _helpers.psql
select plan(32);

create temp table t as select tests.person('Rafa') as rafa, tests.person('Ana') as ana;
alter table t add column pair uuid;
update t set pair = tests.pair(rafa, ana, tests.at('2026-11-01 12:00'));

create function tests.ledger_balanced(p_user uuid, p_at timestamptz) returns boolean language sql as $$
  select coalesce((select sum(minutes) from public.minute_ledger where user_id = p_user and created_at <= p_at), 0)
       = public.balance_of(p_user, p_at)
         + coalesce((select sum(remaining) from public.minute_lots
                     where user_id = p_user and closed_at is null and expires_at <= p_at), 0);
$$;

-- ---------------------------------------------------------------------------
-- Default allowance 15; a session runs for what is left; only minutes used are borrowed
-- ---------------------------------------------------------------------------
select is(public.emergency_status(rafa, tests.at('2026-11-10 20:00')) ->> 'remaining', '15', 'the default allowance is 15 minutes a week') from t;
create temp table s1 as select (public.api_emergency_unlock(rafa, gen_random_uuid(), tests.at('2026-11-10 20:00')) -> 'unlock' ->> 'id')::uuid as id from t;
select is((select minutes from public.unlocks where id = (select id from s1)), 15, 'the first session can run for all 15');
select is(public.balance_of(rafa, tests.at('2026-11-10 20:01')), 0, 'nothing is borrowed while it runs') from t;
select is((public.api_emergency_unlock(rafa, gen_random_uuid(), tests.at('2026-11-10 20:01')) -> 'unlock' ->> 'id')::uuid,
  (select id from s1), 'starting again while a session runs returns the running session') from t;

-- Ended after 2 minutes: the balance is −2 and 13 minutes remain (device script 8).
create temp table e1 as select public.api_end_unlock_early((select rafa from t), id, tests.at('2026-11-10 20:02')) as v from s1;
select is((select (v -> 'unlock' ->> 'minutes_used')::int from e1), 2, 'ending after 2 minutes counts 2 minutes used');
select is(public.balance_of(rafa, tests.at('2026-11-10 20:03')), -2, 'and borrows only those 2') from t;
select is((select v -> 'emergency' ->> 'remaining' from e1), '13', '13 emergency minutes stay available');
select is((select (v -> 'emergency' ->> 'renews_at')::timestamptz from e1), tests.at('2026-11-17 20:00'),
  'they renew 7 days after the first use');
select is((public.api_end_unlock_early((select rafa from t), id, tests.at('2026-11-10 20:05')) ->> 'replayed'), 'true',
  'ending the same session again changes nothing') from s1;
select ok(tests.ledger_balanced(rafa, tests.at('2026-11-10 20:06')), 'the ledger explains the balance') from t;

-- A second session uses the remainder; running to its end borrows all of it.
create temp table s2 as select (public.api_emergency_unlock(rafa, gen_random_uuid(), tests.at('2026-11-12 21:00')) -> 'unlock' ->> 'id')::uuid as id from t;
select is((select minutes from public.unlocks where id = (select id from s2)), 13, 'a second session runs for the remaining 13');
select is(public.settle_all_emergency_unlocks(tests.at('2026-11-12 21:12')), 0, 'it is not settled before it ends');
select is(public.settle_all_emergency_unlocks(tests.at('2026-11-12 21:13')), 1, 'when it runs out it is settled');
select is(public.balance_of(rafa, tests.at('2026-11-12 21:14')), -15, 'having borrowed all 13') from t;
select throws_ok(
  format($q$select public.api_emergency_unlock(%L, %L, %L)$q$, (select rafa from t), gen_random_uuid(), tests.at('2026-11-13 21:00')),
  'CAERR', 'allowance_used_up', 'a third attempt the same week is refused');
select is(public.emergency_status(rafa, tests.at('2026-11-17 20:00')) ->> 'remaining', '15', 'seven days after the first use, the full allowance is back') from t;

-- Streak once per day; a note to the partner per session.
select public.api_end_unlock_early(rafa, (public.api_emergency_unlock(rafa, gen_random_uuid(), tests.at('2026-11-17 20:10')) -> 'unlock' ->> 'id')::uuid,
  tests.at('2026-11-17 20:12')) from t;
select public.api_emergency_unlock(rafa, gen_random_uuid(), tests.at('2026-11-17 22:00')) from t;
select is((select count(*)::int from public.daily_pair_status where pair_id = (select pair from t) and day = '2026-11-17' and broke_streak), 1,
  'two sessions on one day break the streak once');
select is((select count(*)::int from public.notifications_outbox where kind = 'emergency_used' and user_id = (select ana from t)), 4,
  'the partner gets a neutral note for each session');

-- Rounding: 61 seconds is 2 minutes used.
create temp table u2 as select tests.person('Bea') as bea;
create temp table s3 as select (public.api_emergency_unlock(bea, gen_random_uuid(), tests.at('2026-11-10 08:00')) -> 'unlock' ->> 'id')::uuid as id from u2;
select is((public.api_end_unlock_early((select bea from u2), id, tests.at('2026-11-10 08:00') + interval '61 seconds') -> 'unlock' ->> 'minutes_used')::int,
  2, '61 seconds of use rounds up to 2 minutes') from s3;

-- ---------------------------------------------------------------------------
-- Changing the allowance mid-week: remaining = new allowance − used, never below zero
-- ---------------------------------------------------------------------------
-- Bea has used 2 of 15.
update public.user_settings set emergency_allowance_minutes = 30 where user_id = (select bea from u2);
select is(public.emergency_status(bea, tests.at('2026-11-11 08:00')) ->> 'remaining', '28', 'raising it to 30 leaves 28') from u2;
select public.api_emergency_unlock(bea, gen_random_uuid(), tests.at('2026-11-11 09:00')) from u2; -- uses all 28 (running)
update public.user_settings set emergency_allowance_minutes = 15 where user_id = (select bea from u2);
select is(public.emergency_status(bea, tests.at('2026-11-11 10:00')) ->> 'remaining', '0', 'lowering it below what was used leaves 0, never less') from u2;
select throws_ok(format($q$update public.user_settings set emergency_allowance_minutes = 20 where user_id = %L$q$, (select bea from u2)),
  '23514', null, 'only 15, 30, 45 or 60 are allowed');
select throws_ok(format($q$update public.user_settings set emergency_allowance_minutes = 0 where user_id = %L$q$, (select bea from u2)),
  '23514', null, 'and it can never be turned off');

-- ---------------------------------------------------------------------------
-- Ending a minutes unlock early refunds unused whole minutes to their original lots
-- ---------------------------------------------------------------------------
create temp table m as select tests.person('Caio') as caio;
-- Lot A: 10 minutes expiring sooner; lot B: 50 minutes expiring later.
select public.grant_minutes(caio, null, 10, 'earn_kudos', null, null, tests.at('2026-11-08 12:00')) from m;
select public.grant_minutes(caio, null, 50, 'earn_kudos', null, null, tests.at('2026-11-09 12:00')) from m;
create temp table mu as select (public.api_spend_minutes_unlock(caio, 30, gen_random_uuid(), tests.at('2026-11-10 20:00')) -> 'unlock' ->> 'id')::uuid as id from m;
select is(public.balance_of(caio, tests.at('2026-11-10 20:01')), 30, 'a 30-minute unlock spends 30 (10 from A, 20 from B)') from m;
create temp table me as select public.api_end_unlock_early((select caio from m), id, tests.at('2026-11-10 20:09:30')) as v from mu;
select is((select (v ->> 'refunded')::int from me), 20, 'ended 9½ minutes in: the 20 unused whole minutes come back');
select is(public.balance_of(caio, tests.at('2026-11-10 20:10')), 50, 'so the balance is 50') from m;
select is((select remaining from public.minute_lots where user_id = (select caio from m) and granted = 50), 50,
  'refunds go to the latest-expiring lot first, keeping its expiry');
select is((select expires_at from public.minute_lots where user_id = (select caio from m) and granted = 50), tests.at('2026-11-16 12:00'),
  'the refunded minutes keep their original expiry');
select is(public.spent_today(caio, tests.at('2026-11-10 20:10')), 10, 'only the 10 used count toward today''s maximum') from m;
select ok(tests.ledger_balanced(caio, tests.at('2026-11-10 20:10')), 'the ledger explains the balance after a refund') from m;

-- ---------------------------------------------------------------------------
-- Free unlocks just end; an unlock that is over cannot be ended
-- ---------------------------------------------------------------------------
create temp table q as select public.new_unlock((select rafa from t), (select pair from t), 'partner_approval', 30, tests.at('2026-11-20 20:00')) as u;
select is((public.api_end_unlock_early((select rafa from t), (select (u).id from q), tests.at('2026-11-20 20:05')) -> 'unlock' ->> 'minutes_used')::int,
  5, 'a partner-approved unlock just ends (5 minutes used, nothing to refund or borrow)');
create temp table q2 as select public.new_unlock((select rafa from t), (select pair from t), 'qr', 15, tests.at('2026-11-20 21:00')) as u;
select throws_ok(format($q$select public.api_end_unlock_early(%L, %L, %L)$q$, (select rafa from t), (select (u).id from q2), tests.at('2026-11-20 21:20')),
  'CAERR', 'not_active', 'an unlock that is already over cannot be ended');

select * from finish();
rollback;
