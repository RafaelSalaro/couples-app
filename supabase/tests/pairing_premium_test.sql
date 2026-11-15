-- Pairing (docs/03 §3) and premium (docs/03 §12, docs/07 §3 "Premium").
begin;
\ir _helpers.psql
select plan(24);

create temp table t as
select tests.person('Rafa') as rafa, tests.person('Ana') as ana, tests.person('Bea') as bea, tests.person('Caio') as caio;

-- ---------------------------------------------------------------------------
-- Invites: code or link, 72 hours, stored as hashes
-- ---------------------------------------------------------------------------
create temp table inv as select public.api_create_invite(rafa, tests.at('2026-11-01 10:00')) as v from t;
select matches((select v ->> 'code' from inv), '^[A-HJKMNP-Z2-9]{6}$', 'the invite code is 6 easy-to-read characters');
select is((select code_hash from public.invites where id = (select (v ->> 'id')::uuid from inv)),
  public.sha256_hex((select v ->> 'code' from inv)), 'only hashes of the code and link are stored');
select is((select expires_at from public.invites where id = (select (v ->> 'id')::uuid from inv)),
  tests.at('2026-11-04 10:00'), 'an invite lasts 72 hours');
select throws_ok(
  format($q$select public.api_accept_invite(%L, %L, %L)$q$, (select rafa from t), (select v ->> 'code' from inv), tests.at('2026-11-01 10:05')),
  'CAERR', 'invalid', 'nobody can accept their own invite');
select throws_ok(
  format($q$select public.api_accept_invite(%L, %L, %L)$q$, (select ana from t), (select v ->> 'code' from inv), tests.at('2026-11-04 10:00')),
  'CAERR', 'expired', 'an invite cannot be used after 72 hours');

create temp table acc as
select public.api_accept_invite(ana, lower(v ->> 'code'), tests.at('2026-11-01 10:10')) as v from t, inv;
select ok((select v ->> 'qr_secret' from acc) ~ '^[A-Z2-7]{32}$', 'pairing returns a 160-bit base32 QR secret (typed codes ignore case)');
select ok(public.balance_of(rafa, tests.at('2026-11-01 10:11')) = 30 and public.balance_of(ana, tests.at('2026-11-01 10:11')) = 30,
  'both start with 30 minutes') from t;
select is(public.api_accept_invite((select ana from t), (select v ->> 'link_token' from inv), tests.at('2026-11-01 10:12')) ->> 'pair_id',
  (select v ->> 'pair_id' from acc), 'opening the link again returns the same pair');
select throws_ok(
  format($q$select public.api_create_invite(%L, %L)$q$, (select ana from t), tests.at('2026-11-01 11:00')),
  'CAERR', 'already_paired', 'inviting while paired is refused');

-- ---------------------------------------------------------------------------
-- Pair premium when the payer is active; trial counted once per pair
-- ---------------------------------------------------------------------------
select ok(not public.is_premium(ana, tests.at('2026-11-02 10:00')), 'no premium before anyone pays') from t;
select public.api_apply_entitlement(rafa, 'yearly', 'trial', true, tests.at('2026-11-16 10:00'), 'app_store',
                                    tests.at('2026-11-02 10:00'), tests.at('2026-11-02 10:00')) from t;
select ok(public.is_premium(ana, tests.at('2026-11-03 10:00')), 'Rafa''s trial covers Ana too') from t;
select is((select trial_user_id from public.pairs where id = (select (v ->> 'pair_id')::uuid from acc)),
  (select rafa from t), 'the pair''s one trial is recorded');
select ok(not public.is_premium(ana, tests.at('2026-11-17 10:00')), 'when the trial ends, premium ends for both') from t;

select public.api_apply_entitlement(ana, 'yearly', 'trial', true, tests.at('2026-12-01 10:00'), 'app_store',
                                    tests.at('2026-11-17 11:00'), tests.at('2026-11-17 11:00')) from t;
select ok(public.recompute_coverage((select (v ->> 'pair_id')::uuid from acc), tests.at('2026-11-17 12:00')) is null,
  'a second trial in the same pair does not cover it');
select ok(not public.is_premium(rafa, tests.at('2026-11-17 12:00')), 'so Rafa has no premium from Ana''s trial') from t;

select public.api_apply_entitlement(ana, 'yearly', 'subscription', true, tests.at('2027-11-18 10:00'), 'app_store',
                                    tests.at('2026-11-18 10:00'), tests.at('2026-11-18 10:00')) from t;
select ok(public.is_premium(rafa, tests.at('2026-11-19 10:00')), 'Ana''s paid subscription covers Rafa') from t;
-- An older event arriving late is ignored.
select public.api_apply_entitlement(ana, 'yearly', 'subscription', false, null, 'app_store',
                                    tests.at('2026-11-17 09:00'), tests.at('2026-11-19 10:00')) from t;
select ok(public.is_premium(rafa, tests.at('2026-11-19 11:00')), 'an out-of-date webhook event does not undo a newer one') from t;

-- ---------------------------------------------------------------------------
-- Unpair: instant, minutes to zero, pending items cancelled; premium stays with the payer
-- ---------------------------------------------------------------------------
select public.api_create_unlock_request(rafa, 30, null, tests.at('2026-11-20 20:00')) from t;
select public.api_unpair(rafa, tests.at('2026-11-20 20:01')) from t;
select ok(public.active_pair_of(rafa) is null and public.active_pair_of(ana) is null, 'either partner can unpair at once') from t;
select ok(public.balance_of(rafa, tests.at('2026-11-20 20:02')) = 0 and public.balance_of(ana, tests.at('2026-11-20 20:02')) = 0,
  'both balances go to zero') from t;
select is((select status::text from public.unlock_requests order by created_at desc limit 1), 'cancelled', 'open requests are cancelled');
select ok(public.is_premium(ana, tests.at('2026-11-20 20:02')) and not public.is_premium(rafa, tests.at('2026-11-20 20:02')),
  'the payer keeps premium; the other partner loses it') from t;

-- ---------------------------------------------------------------------------
-- Changing the covered partner: at most once per 30 days
-- ---------------------------------------------------------------------------
-- Ana began covering Rafa on 18 November. She pairs with Bea on 21 November: her
-- subscription cannot move to Bea until 30 days after it started covering Rafa.
create temp table p2 as select tests.pair(ana, bea, tests.at('2026-11-21 10:00')) as pair from t;
select ok(public.recompute_coverage(pair, tests.at('2026-11-21 10:00')) is null, 'a covered-partner change within 30 days is blocked') from p2;
select ok(not public.is_premium(bea, tests.at('2026-11-21 10:00')), 'so Bea is not covered yet') from t;
select is(public.recompute_coverage(pair, tests.at('2026-12-19 10:00')), (select ana from t), 'after 30 days the change goes through') from p2;

select * from finish();
rollback;
