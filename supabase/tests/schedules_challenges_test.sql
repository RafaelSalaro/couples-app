-- Schedules (docs/03 §4, docs/07 §3 "Schedules"), challenges and kudos (docs/03 §8),
-- export and account deletion (docs/03 §13–14).
begin;
\ir _helpers.psql
select plan(29);

create temp table t as select tests.person('Rafa') as rafa, tests.person('Ana') as ana, tests.person('Solo') as solo;
alter table t add column pair uuid;
update t set pair = tests.pair(rafa, ana, tests.at('2026-11-01 12:00'));

-- ---------------------------------------------------------------------------
-- 18:00–09:00 every day: protected at 23:00, 02:00, 08:59; not at 09:00 or 17:59
-- ---------------------------------------------------------------------------
create temp table s as
select (public.api_propose_schedule_change(rafa, null, jsonb_build_object('kind', 'schedule', 'schedule',
  jsonb_build_object('weekdays', jsonb_build_array(1,2,3,4,5,6,7), 'start_local', '18:00:00', 'end_local', '09:00:00')),
  tests.at('2026-11-01 12:00')) -> 'schedule' ->> 'id')::uuid as id from t;
select ok(public.is_protected(rafa, tests.at('2026-11-10 23:00')), 'protected at 23:00') from t;
select ok(public.is_protected(rafa, tests.at('2026-11-11 02:00')), 'protected at 02:00, across midnight') from t;
select ok(public.is_protected(rafa, tests.at('2026-11-11 08:59')), 'protected at 08:59') from t;
select ok(not public.is_protected(rafa, tests.at('2026-11-11 09:00')), 'not protected at 09:00') from t;
select ok(not public.is_protected(rafa, tests.at('2026-11-11 17:59')), 'not protected at 17:59') from t;

-- Daylight saving in New York: clocks go back at 2:00 on 1 November 2026, forward on 8 March 2026.
select ok(public.is_protected(rafa, '2026-11-01 06:30+00'), 'the repeated 1:30 AM of the fall-back night is protected (first)') from t;
select ok(public.is_protected(rafa, '2026-11-01 05:30+00'), 'and the earlier 1:30 AM too') from t;
select ok(not public.is_protected(rafa, tests.at('2026-11-01 09:00')), 'the fall-back night still ends at 9:00 local') from t;
select ok(public.is_protected(rafa, tests.at('2026-03-08 03:30')) and not public.is_protected(rafa, tests.at('2026-03-08 09:00')),
  'the spring-forward night is protected after the jump and ends at 9:00 local') from t;

-- Weekdays only: a Friday-evening window runs into Saturday morning, Saturday evening is free.
select ok(public.schedule_protects(array[1,2,3,4,5]::smallint[], '18:00', '09:00', 'America/New_York', tests.at('2026-11-14 08:00')),
  'Friday''s window covers Saturday morning');
select ok(not public.schedule_protects(array[1,2,3,4,5]::smallint[], '18:00', '09:00', 'America/New_York', tests.at('2026-11-14 20:00')),
  'no window starts on Saturday');

-- ---------------------------------------------------------------------------
-- Stricter applies now; looser waits for the partner; unpaired applies directly
-- ---------------------------------------------------------------------------
select is(public.api_propose_schedule_change(rafa, id, jsonb_build_object('kind', 'schedule', 'schedule',
  jsonb_build_object('weekdays', jsonb_build_array(1,2,3,4,5,6,7), 'start_local', '17:00:00', 'end_local', '09:00:00')),
  tests.at('2026-11-02 12:00')) ->> 'applied', 'true', 'starting earlier is stricter and applies at once') from t, s;
create temp table looser as
select public.api_propose_schedule_change(rafa, id, jsonb_build_object('kind', 'schedule', 'schedule',
  jsonb_build_object('weekdays', jsonb_build_array(1,2,3,4,5,6,7), 'start_local', '19:00:00', 'end_local', '09:00:00')),
  tests.at('2026-11-02 12:05')) as v from t, s;
select is((select v ->> 'applied' from looser), 'false', 'starting later is looser and asks the partner');
select is((select start_local from public.schedules where id = (select id from s)), '17:00'::time, 'nothing changes until then');
select is((select expires_at from public.schedule_change_requests), tests.at('2026-11-03 12:05'), 'the request waits 24 hours');
select is(public.api_respond_schedule_change((select ana from t), (select (v -> 'request' ->> 'id')::uuid from looser), true,
  tests.at('2026-11-02 13:00')) -> 'schedule' ->> 'start_local', '19:00:00', 'once the partner approves it applies');
select is(public.api_propose_schedule_change(rafa, id, '{"kind": "fewer_paused_apps"}', tests.at('2026-11-02 14:00')) ->> 'applied',
  'false', 'pausing fewer apps asks the partner') from t, s;
select is(public.api_propose_schedule_change(solo, null, jsonb_build_object('kind', 'schedule', 'schedule',
  jsonb_build_object('weekdays', jsonb_build_array(6,7), 'start_local', '22:00:00', 'end_local', '07:00:00')),
  tests.at('2026-11-02 12:00')) ->> 'applied', 'true', 'unpaired, every change applies directly') from t;
select throws_ok(
  format($q$select public.api_propose_schedule_change(%L, null, %L, %L)$q$, (select solo from t),
    '{"kind": "schedule", "schedule": {"weekdays": [1], "start_local": "20:00:00", "end_local": "21:00:00"}}', tests.at('2026-11-02 12:00')),
  'CAERR', 'premium_required', 'a second schedule needs premium');

-- ---------------------------------------------------------------------------
-- Challenges: done → partner confirms → minutes; shared grants both; 48 hours
-- ---------------------------------------------------------------------------
create temp table ch as
select (select id from public.challenges where title = 'Write your partner a note' and pair_id is null) as note,
       (select id from public.challenges where title = 'Walk together without phones' and pair_id is null) as walk,
       (select id from public.challenges where tier = 'premium' and pair_id is null limit 1) as premium;
create temp table c1 as
select (public.api_complete_challenge((select rafa from t), note, 'On the fridge', null, tests.at('2026-11-05 18:00')) ->> 'id')::uuid as id from ch;
select is((public.api_complete_challenge((select rafa from t), (select note from ch), null, null, tests.at('2026-11-05 18:01')) ->> 'id')::uuid,
  (select id from c1), 'tapping Done twice does not create a second completion');
select throws_ok(
  format($q$select public.api_confirm_completion(%L, %L, %L)$q$, (select rafa from t), (select id from c1), tests.at('2026-11-05 18:02')),
  'CAERR', 'not_partner', 'nobody confirms their own challenge');
select public.api_confirm_completion((select ana from t), id, tests.at('2026-11-05 19:00')) from c1;
select is(public.balance_of(rafa, tests.at('2026-11-05 19:01')), 10, 'confirmed: the doer earns the challenge''s minutes') from t;

create temp table c2 as
select (public.api_complete_challenge((select ana from t), walk, null, null, tests.at('2026-11-06 18:00')) ->> 'id')::uuid as id from ch;
select public.api_confirm_completion((select rafa from t), id, tests.at('2026-11-06 19:00')) from c2;
select ok(public.balance_of(rafa, tests.at('2026-11-06 19:01')) = 30 and public.balance_of(ana, tests.at('2026-11-06 19:01')) = 20,
  'a shared challenge grants both on one confirmation') from t;

create temp table c3 as
select (public.api_complete_challenge((select rafa from t), note, null, null, tests.at('2026-11-07 18:00')) ->> 'id')::uuid as id from ch;
select is(public.api_confirm_completion((select ana from t), id, tests.at('2026-11-09 18:00')) ->> 'error', 'expired',
  'a completion not confirmed within 48 hours expires') from c3;
select throws_ok(
  format($q$select public.api_complete_challenge(%L, %L, null, null, %L)$q$, (select rafa from t), (select premium from ch), tests.at('2026-11-07 18:00')),
  'CAERR', 'premium_required', 'the full library needs premium');

-- ---------------------------------------------------------------------------
-- Kudos: premium, 5–30 minutes, 60 per giver per day
-- ---------------------------------------------------------------------------
select throws_ok(
  format($q$select public.api_give_kudos(%L, 10, 'You made me laugh', null, %L)$q$, (select ana from t), tests.at('2026-11-08 20:00')),
  'CAERR', 'premium_required', 'kudos are premium');
select public.api_apply_entitlement(ana, 'lifetime', 'lifetime', true, null, 'app_store', tests.at('2026-11-08 10:00'), tests.at('2026-11-08 10:00')) from t;
select public.api_give_kudos(ana, 30, 'Dinner', null, tests.at('2026-11-08 20:00')) from t;
select public.api_give_kudos(ana, 30, 'Dishes', null, tests.at('2026-11-08 21:00')) from t;
select throws_ok(
  format($q$select public.api_give_kudos(%L, 5, 'More', null, %L)$q$, (select ana from t), tests.at('2026-11-08 22:00')),
  'CAERR', 'daily_cap', 'no more than 60 minutes of kudos per day');

-- ---------------------------------------------------------------------------
-- Export and deletion
-- ---------------------------------------------------------------------------
select ok(jsonb_array_length(public.api_export_my_data(rafa) -> 'minute_ledger') > 0
          and not (public.api_export_my_data(rafa)::text like '%code_hash%'),
  'export holds the person''s ledger and no secret hashes') from t;
select public.api_delete_account(rafa, tests.at('2026-11-09 12:00')) from t;
select ok(not exists (select 1 from public.profiles where id = (select rafa from t))
          and not exists (select 1 from public.minute_ledger where user_id = (select rafa from t))
          and public.active_pair_of((select ana from t)) is null,
  'deleting the account removes the person''s data and unpairs the partner');

select * from finish();
rollback;
