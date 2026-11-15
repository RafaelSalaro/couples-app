-- Regression tests for the fixes from the backend security review (docs/security-review-backend.md).
begin;
\ir _helpers.psql
select plan(16);

create temp table t as select tests.person('Rafa') as rafa, tests.person('Ana') as ana, tests.person('Eve') as eve;
grant select on t to authenticated, anon, service_role;
select public.api_accept_invite(ana, public.api_create_invite(rafa) ->> 'code') from t;
create function tests.as_user(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
grant usage on schema tests to authenticated, anon;
grant execute on function tests.as_user(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- R1. Requests are readable in full by the pair; the secrets are not readable by anyone
-- ---------------------------------------------------------------------------
create temp table req as select (public.api_create_unlock_request(rafa, 30, null) ->> 'id')::uuid as id from t;
grant select on req to authenticated;
select public.issue_unlock_email_secrets(id) from req;
set local role authenticated;
select tests.as_user(ana) from t;
select is((select count(*)::int from (select * from public.unlock_requests) r), 1,
  'the partner can select * on the pair''s requests (the app''s query)');
select tests.as_user(rafa) from t;
select throws_ok($q$select code_hash from public.unlock_request_secrets$q$, '42501', null,
  'the requester cannot read the accountability code''s hash');
reset role;

-- ---------------------------------------------------------------------------
-- R2. Guessing invite codes is limited to 10 tries an hour, failed tries included
-- ---------------------------------------------------------------------------
select public.api_accept_invite(eve, 'ZZZZZ' || n::text, tests.at('2026-11-15 10:00')) from t, generate_series(1, 9) n;
select is(public.api_accept_invite(eve, 'ZZZZZY', tests.at('2026-11-15 10:01')) ->> 'error', 'invalid',
  'the 10th try in an hour is still checked') from t;
select is(public.api_accept_invite(eve, 'ZZZZZX', tests.at('2026-11-15 10:02')) ->> 'error', 'rate_limited',
  'the 11th is refused before the code is looked at') from t;
select is(public.api_accept_invite(eve, 'ZZZZZW', tests.at('2026-11-15 11:01')) ->> 'error', 'invalid',
  'the next hour, trying is allowed again') from t;

-- ---------------------------------------------------------------------------
-- R3. The phone reports protected time off; the server stamps the time and tells the partner
-- ---------------------------------------------------------------------------
set local role authenticated;
select tests.as_user(rafa) from t;
select lives_ok($q$update public.profiles set protected_time_off_since = '2020-01-01' where id = auth.uid()$q$,
  'a phone can report that protected time is off');
reset role;
select ok((select protected_time_off_since > now() - interval '1 minute' from public.profiles where id = (select rafa from t)),
  'the server stamps the time itself (a back-dated value is replaced)');
select is((select count(*)::int from public.notifications_outbox where user_id = (select ana from t) and kind = 'protected_time_off'), 1,
  'the partner gets the neutral note');
select ok(exists (select 1 from public.daily_pair_status where broke_streak and reason = 'protected_time_off'),
  'the day breaks the shared streak');
set local role authenticated;
select tests.as_user(rafa) from t;
update public.profiles set protected_time_off_since = null where id = auth.uid();
reset role;
select is((select count(*)::int from public.notifications_outbox where user_id = (select ana from t) and kind = 'protected_time_on'), 1,
  'turning it back on tells the partner too');
set local role authenticated;
select tests.as_user(rafa) from t;
select throws_ok($q$update public.profiles set deleted_at = now() where id = auth.uid()$q$, '42501', null,
  'other profile columns stay closed to the phone');

-- ---------------------------------------------------------------------------
-- R4. Registering a push token twice works, and only for yourself
-- ---------------------------------------------------------------------------
select lives_ok($q$insert into public.push_tokens (user_id, platform, token, environment) values (auth.uid(), 'ios', 'tok-rafa-0001', 'sandbox')
  on conflict (user_id, token) do update set user_id = excluded.user_id, environment = excluded.environment$q$,
  'the app''s upsert of its push token works, also the second time');
select lives_ok($q$insert into public.push_tokens (user_id, platform, token, environment) values (auth.uid(), 'ios', 'tok-rafa-0001', 'production')
  on conflict (user_id, token) do update set user_id = excluded.user_id, environment = excluded.environment$q$,
  'and updates the environment');
select throws_ok(format($q$update public.push_tokens set user_id = %L where user_id = auth.uid()$q$, (select eve from t)),
  '42501', null, 'a token cannot be moved to someone else');
reset role;

-- ---------------------------------------------------------------------------
-- R5. Smaller hardening
-- ---------------------------------------------------------------------------
select public.api_apply_entitlement(ana, 'lifetime', 'lifetime', true, null, 'app_store', now(), now()) from t;
create temp table other as select tests.pair((select eve from t), tests.person('Zed')) as pair;
insert into public.challenges (pair_id, title, minutes, category, status) select pair, 'Their private challenge', 10, 'together', 'active' from other;
select throws_ok(format($q$select public.api_give_kudos(%L, 10, '', %L)$q$, (select ana from t),
                        (select id from public.challenges where title = 'Their private challenge')),
  'CAERR', 'invalid_input', 'kudos cannot point at another pair''s challenge');
set local role anon;
select throws_ok($q$select public.is_pair_member(gen_random_uuid())$q$, '42501', null,
  'the anonymous role cannot call the RLS helpers');
reset role;

select * from finish();
rollback;
