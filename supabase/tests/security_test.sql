-- Privileges and Row Level Security: docs/05 §2, docs/04 §4.
begin;
\ir _helpers.psql
select plan(12);

create temp table t as
select tests.person('Rafa') as rafa, tests.person('Ana') as ana, tests.person('Eve') as eve;
grant select on t to authenticated, anon;
select public.api_accept_invite(ana, public.api_create_invite(rafa) ->> 'code') from t;

-- Act as a signed-in client.
create function tests.as_user(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
grant usage on schema tests to authenticated, anon;
grant execute on function tests.as_user(uuid) to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Clients can never call the engine
-- ---------------------------------------------------------------------------
set local role authenticated;
select tests.as_user(rafa) from t;
select throws_ok(
  format($q$select public.grant_minutes(%L, null, 999, 'admin_adjust')$q$, (select rafa from t)),
  '42501', null, 'a client cannot grant itself minutes');
select throws_ok(
  format($q$select public.api_spend_minutes_unlock(%L, 15, gen_random_uuid())$q$, (select rafa from t)),
  '42501', null, 'a client cannot call api_* functions directly (only Edge Functions can)');
select throws_ok($q$insert into public.minute_lots (user_id, granted, remaining, expires_at) values (auth.uid(), 99, 99, now() + interval '1 day')$q$,
  '42501', null, 'a client cannot write minutes');

-- ---------------------------------------------------------------------------
-- Reading: own and partner's rows only
-- ---------------------------------------------------------------------------
select is((select count(*)::int from public.minute_lots), 2, 'Rafa sees his and Ana''s minutes');
select is((select count(*)::int from public.pair_secrets), 1, 'and the pair''s QR secret');
select is((select count(*)::int from public.profiles where id = (select eve from t)), 0, 'but nothing about a stranger');

reset role;
set local role authenticated;
select tests.as_user(eve) from t;
select is((select count(*)::int from public.minute_lots), 0, 'a stranger sees nobody''s minutes');
select is((select count(*)::int from public.pair_secrets), 0, 'a stranger cannot read the pair''s secret');
select is((select count(*)::int from public.unlock_requests), 0, 'or their requests');

-- After unpairing the secret is gone for both.
reset role;
select public.api_unpair(rafa) from t;
set local role authenticated;
select tests.as_user(ana) from t;
select is((select count(*)::int from public.pair_secrets), 0, 'after unpairing nobody holds the old secret');

-- ---------------------------------------------------------------------------
-- The anonymous role reads nothing
-- ---------------------------------------------------------------------------
reset role;
set local role anon;
select throws_ok($q$select count(*) from public.profiles$q$, '42501', null, 'anonymous visitors cannot read profiles');
select throws_ok($q$select count(*) from public.waitlist$q$, '42501', null, 'or the waitlist');

reset role;
select * from finish();
rollback;
