-- Scheduled jobs, outbox, waitlist and the approve link: docs/05 §4, web/README.md.
begin;
\ir _helpers.psql
select plan(21);

create temp table t as select tests.person('Rafa') as rafa, tests.person('Ana') as ana;
alter table t add column pair uuid;
update t set pair = (public.api_accept_invite(ana, public.api_create_invite(rafa, tests.at('2026-11-01 10:00')) ->> 'code',
                                             tests.at('2026-11-01 10:05')) ->> 'pair_id')::uuid;

-- ---------------------------------------------------------------------------
-- Outbox: claimed once, retried with a pause, never shared by two senders
-- ---------------------------------------------------------------------------
delete from public.notifications_outbox;
select public.enqueue_notification(ana, 'kudos_received', jsonb_build_object('from_user_id', rafa, 'minutes', 10)) from t;
create temp table c as select public.claim_outbox(10) as v;
select is(jsonb_array_length((select v from c)), 1, 'a due row is claimed');
select is((select v -> 0 ->> 'from_name' from c), 'Rafa', 'with the sender''s name');
select is((select v -> 0 ->> 'email' from c), (select email::text from auth.users where id = (select ana from t)), 'and the recipient''s email');
select is(jsonb_array_length(public.claim_outbox(10)), 0, 'a claimed row is not handed out again while it is being sent');
select public.finish_outbox((select (v -> 0 ->> 'id')::uuid from c), 'retry', now());
select ok((select status = 'queued' and send_after > now() from public.notifications_outbox), 'a retry waits before the next attempt');
select public.finish_outbox((select (v -> 0 ->> 'id')::uuid from c), 'sent');
select is((select status::text from public.notifications_outbox), 'sent', 'sent rows are marked sent');

-- Muted categories are not queued; unlock requests cannot be muted.
update public.user_settings set notification_prefs = '{"kudos": false, "request_updates": false}' where user_id = (select ana from t);
select is(public.enqueue_notification(ana, 'kudos_received', '{}'), null::uuid, 'a muted category is not queued') from t;
select isnt(public.enqueue_notification(ana, 'unlock_request', '{}'), null::uuid, 'unlock requests always are') from t;

-- ---------------------------------------------------------------------------
-- Every minute: requests past 5 minutes expire and the requester hears so
-- ---------------------------------------------------------------------------
select public.api_create_unlock_request(rafa, 15, null, tests.at('2026-11-10 20:00')) from t;
select is(public.expire_requests(tests.at('2026-11-10 20:04')), 0, 'nothing expires before 5 minutes');
select is(public.expire_requests(tests.at('2026-11-10 20:05')), 1, 'at 5 minutes the request expires');
select is((select count(*)::int from public.notifications_outbox where kind = 'unlock_expired' and user_id = (select rafa from t)), 1,
  'and the requester is told');

-- ---------------------------------------------------------------------------
-- The approve link in the fallback email
-- ---------------------------------------------------------------------------
create temp table req as select (public.api_create_unlock_request(rafa, 30, null, tests.at('2026-11-10 21:00')) ->> 'id')::uuid as id from t;
create temp table tok as select public.issue_unlock_email_secrets(id, tests.at('2026-11-10 21:02')) ->> 'approve_token' as token from req;
select is(public.api_respond_unlock_by_token((select token from tok), true, tests.at('2026-11-10 21:03')) -> 'request' ->> 'status',
  'approved', 'the link in the email approves as the partner');
select throws_ok($q$select public.api_respond_unlock_by_token('made-up', true)$q$, 'CAERR', 'invalid', 'an unknown link does nothing');

-- ---------------------------------------------------------------------------
-- 7 PM local: minutes that expire tomorrow (once a day)
-- ---------------------------------------------------------------------------
select public.grant_minutes(ana, pair, 20, 'earn_kudos', null, null, tests.at('2026-11-11 12:00')) from t;
select is(public.expiry_reminder(tests.at('2026-11-17 18:00')), 0, 'not before 7 PM');
select is(public.expiry_reminder(tests.at('2026-11-17 19:00')), 1, 'at 7 PM the evening before, one reminder');
select is(public.expiry_reminder(tests.at('2026-11-17 19:30')), 0, 'and only one');

-- ---------------------------------------------------------------------------
-- Sunday 7 PM: the weekly report, in the shape the app reads
-- ---------------------------------------------------------------------------
select is(public.weekly_reports_job(tests.at('2026-11-15 19:00')), 1, 'Sunday at 7 PM the pair''s report is built');
select ok((select data ? 'members' and data ? 'total_earned_together' and data ? 'protected_hours' from public.weekly_reports),
  'with the fields the app reads');

-- ---------------------------------------------------------------------------
-- Waitlist: double opt-in; joining twice looks the same
-- ---------------------------------------------------------------------------
select public.api_waitlist_join('New@Example.com ', 'home', 'ip1');
select public.api_waitlist_join('new@example.com', 'home', 'ip1');
select is((select count(*)::int from public.notifications_outbox where kind = 'waitlist_confirm'), 1,
  'joining twice sends one confirmation email');
select ok(public.api_waitlist_confirm((select payload ->> 'token' from public.notifications_outbox where kind = 'waitlist_confirm')),
  'the link in the email is accepted');
select ok((select confirmed_at is not null from public.waitlist), 'and confirms the address');

select * from finish();
rollback;
