-- Two App Review demo accounts, already paired (docs/07 §7, content/app-store/review-notes.md).
-- NOT a seed: run it by hand against the production project, once, before submission:
--
--   psql "$DATABASE_URL" -v email_a=review-a@<domain> -v email_b=review-b@<domain> \
--        -f supabase/demo/review_accounts.sql
--
-- What it sets up for each account: a display name, protected time all day every day (so it
-- is active whenever the reviewer looks), 60 minutes, and one challenge done by B awaiting
-- A's confirmation. Safe to re-run: existing accounts with these emails are left alone.
--
-- Sign-in is still open (founder question 5): these accounts have no password. Whatever
-- reviewer sign-in path is chosen must be added to the app before this is useful.

\set ON_ERROR_STOP on
begin;

create temp table review_ids as
select coalesce((select id from auth.users where email = :'email_a'), gen_random_uuid()) as a,
       coalesce((select id from auth.users where email = :'email_b'), gen_random_uuid()) as b,
       exists (select 1 from auth.users where email = :'email_a') as existed;

insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, now(),
       jsonb_build_object('full_name', name), now(), now()
from review_ids,
     lateral (values (a, :'email_a', 'Alex'), (b, :'email_b', 'Sam')) v(id, email, name)
where not existed;

do $$
declare
  r record;
  v_pair uuid;
  v_completion uuid;
begin
  select * into r from review_ids;
  if r.existed then
    raise notice 'Review accounts already exist; nothing changed.';
    return;
  end if;
  v_pair := (public.api_accept_invite(r.b, public.api_create_invite(r.a) ->> 'code') ->> 'pair_id')::uuid;
  -- Midnight to midnight runs through the whole day (end at or before start = next day).
  perform public.api_propose_schedule_change(u, null,
    '{"kind": "schedule", "schedule": {"weekdays": [1,2,3,4,5,6,7], "start_local": "00:00:00", "end_local": "00:00:00"}}')
    from unnest(array[r.a, r.b]) u;
  perform public.grant_minutes(u, v_pair, 30, 'admin_adjust') from unnest(array[r.a, r.b]) u;
  v_completion := (public.api_complete_challenge(r.b,
    (select id from public.challenges where title = 'Write your partner a note' and pair_id is null), 'For the reviewers') ->> 'id')::uuid;
  raise notice 'Review accounts ready: pair %, completion % awaiting confirmation.', v_pair, v_completion;
end $$;

commit;
