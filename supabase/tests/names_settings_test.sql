-- Names (P27), relationship type hidden (P3) and the new settings columns (P14, P29).
begin;
\ir _helpers.psql
select plan(8);

-- Email sign-up: no name yet ('' until the onboarding name step); Apple: the shared name.
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('cccccccc-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mail@example.com', '{}', now(), now()),
  ('cccccccc-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'apple@example.com', '{"full_name": "  Rafa  "}', now(), now());
select is((select display_name from public.profiles where id = 'cccccccc-0000-4000-8000-000000000001'), '', 'an email sign-up starts without a name');
select is((select display_name from public.profiles where id = 'cccccccc-0000-4000-8000-000000000002'), 'Rafa', 'Sign in with Apple keeps the shared name, trimmed');
select throws_ok($q$update public.profiles set display_name = null where id = 'cccccccc-0000-4000-8000-000000000001'$q$, '23502', null,
  'a name can never be null');
select is((select emergency_allowance_minutes from public.user_settings where user_id = 'cccccccc-0000-4000-8000-000000000001'), 15,
  'the emergency allowance defaults to 15');

-- The phone may set its own allowance and when onboarding finished, nothing else new.
create function tests.as_user(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
grant usage on schema tests to authenticated;
grant execute on function tests.as_user(uuid) to authenticated;
set local role authenticated;
select tests.as_user('cccccccc-0000-4000-8000-000000000001');
select lives_ok($q$update public.user_settings set emergency_allowance_minutes = 30, onboarded_at = now() where user_id = auth.uid()$q$,
  'a phone sets its emergency allowance and that onboarding is done');
select throws_ok($q$update public.unlocks set minutes_used = 0 where user_id = auth.uid()$q$, '42501', null,
  'but cannot touch its unlocks');
reset role;
select is((select emergency_allowance_minutes from public.user_settings where user_id = 'cccccccc-0000-4000-8000-000000000001'), 30, 'saved');

-- Pairs are created as couples; nothing asks for a type (P3).
create temp table p as select (public.api_accept_invite('cccccccc-0000-4000-8000-000000000002',
  public.api_create_invite('cccccccc-0000-4000-8000-000000000001') ->> 'code') ->> 'pair_id')::uuid as id;
select is((select relationship_type::text from public.pairs where id = (select id from p)), 'romantic',
  'a new pair is a couple by default');

select * from finish();
rollback;
