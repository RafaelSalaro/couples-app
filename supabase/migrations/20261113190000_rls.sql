-- WP-3: privileges, Row Level Security policies, profile bootstrap.
--
-- Model (docs/05 §2, docs/04 §4):
--   * Clients (role "authenticated") read their own rows and their pair's rows.
--   * Clients write directly only to: profiles (own row, a few columns), user_settings
--     (own row), push_tokens (own rows), events (insert own).
--   * Everything else is written by Edge Functions with the service role, through SQL
--     functions that no client role may execute.
--   * The anonymous role has no access to any table.

-- ---------------------------------------------------------------------------
-- Privileges: start from nothing for client roles
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- Anything created later is private until a migration grants it.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon, authenticated;

grant all on all tables in schema public to service_role;
-- The ledger is immutable, also for the service role (see trigger below).
revoke update, delete, truncate on public.minute_ledger from service_role;

-- ---------------------------------------------------------------------------
-- Helper functions used by policies
-- SECURITY DEFINER so they can look at pair_members without recursing into its policy.
-- ---------------------------------------------------------------------------
create function public.is_pair_member(p uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.pair_members
    where pair_id = p and user_id = (select auth.uid()) and left_at is null);
$$;

create function public.was_pair_member(p uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.pair_members
    where pair_id = p and user_id = (select auth.uid()));
$$;

-- True when u is the caller's current partner.
create function public.is_partner(u uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.pair_members me
    join public.pair_members them on them.pair_id = me.pair_id
    where me.user_id = (select auth.uid()) and me.left_at is null
      and them.user_id = u and them.left_at is null and them.user_id <> me.user_id);
$$;

grant execute on function public.is_pair_member(uuid) to authenticated, service_role;
grant execute on function public.was_pair_member(uuid) to authenticated, service_role;
grant execute on function public.is_partner(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Profile bootstrap: one profiles, user_settings and minute_debt row per auth user
-- ---------------------------------------------------------------------------
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'), 60))
  on conflict (id) do nothing;
  insert into public.user_settings (user_id) values (new.id) on conflict do nothing;
  insert into public.minute_debt (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Integrity triggers
-- ---------------------------------------------------------------------------

-- time_zone must be a real IANA zone, otherwise local-day math would fail later.
create function public.check_time_zone() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.time_zone) then
    raise exception 'invalid_time_zone' using errcode = '22023';
  end if;
  return new;
end $$;
create trigger profiles_check_time_zone before insert or update of time_zone on public.profiles
  for each row execute function public.check_time_zone();

create function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;
create trigger user_settings_touch before update on public.user_settings
  for each row execute function public.touch_updated_at();
create trigger schedules_touch before update on public.schedules
  for each row execute function public.touch_updated_at();
create trigger push_tokens_touch before update on public.push_tokens
  for each row execute function public.touch_updated_at();

-- Ledger rows are never edited. (Rows are removed only when their owner's account is
-- deleted, by the account-deletion function.)
create function public.forbid_ledger_update() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'minute_ledger is immutable' using errcode = '42501';
end $$;
create trigger minute_ledger_immutable before update on public.minute_ledger
  for each row execute function public.forbid_ledger_update();

-- A device token belongs to one account at a time: registering it removes it elsewhere.
create function public.claim_push_token() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.push_tokens where token = new.token and user_id <> new.user_id;
  return new;
end $$;
create trigger push_tokens_claim before insert on public.push_tokens
  for each row execute function public.claim_push_token();

-- ---------------------------------------------------------------------------
-- Grants and policies per table (role: authenticated)
-- ---------------------------------------------------------------------------

-- profiles: read own and partner's; update a few columns of own row.
grant select on public.profiles to authenticated;
grant update (display_name, photo_path, time_zone, locale) on public.profiles to authenticated;
create policy "read own and partner" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.is_partner(id));
create policy "update own" on public.profiles for update to authenticated
  using (id = (select auth.uid()) and deleted_at is null) with check (id = (select auth.uid()));

-- user_settings: own row; values are bounded by check constraints.
grant select on public.user_settings to authenticated;
grant update (daily_max_minutes, starting_minutes, notification_prefs) on public.user_settings to authenticated;
create policy "read own" on public.user_settings for select to authenticated
  using (user_id = (select auth.uid()));
create policy "update own" on public.user_settings for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- push_tokens: own rows.
grant select, insert, delete on public.push_tokens to authenticated;
grant update (platform, token, environment) on public.push_tokens to authenticated;
create policy "read own" on public.push_tokens for select to authenticated
  using (user_id = (select auth.uid()));
create policy "insert own" on public.push_tokens for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "update own" on public.push_tokens for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "delete own" on public.push_tokens for delete to authenticated
  using (user_id = (select auth.uid()));

-- events: insert own, never read back.
grant insert (user_id, name, props) on public.events to authenticated;
create policy "insert own" on public.events for insert to authenticated
  with check (user_id = (select auth.uid()));

-- pairs and members: read pairs you are or were in; members of your active pair.
grant select on public.pairs to authenticated;
create policy "members read" on public.pairs for select to authenticated
  using (public.was_pair_member(id));
grant select on public.pair_members to authenticated;
create policy "members read" on public.pair_members for select to authenticated
  using (user_id = (select auth.uid()) or public.is_pair_member(pair_id));

-- invites: the inviter sees status, never the hashes.
grant select (id, inviter_id, expires_at, accepted_by, accepted_at, revoked_at, created_at)
  on public.invites to authenticated;
create policy "inviter reads" on public.invites for select to authenticated
  using (inviter_id = (select auth.uid()));

-- schedules: own only. The partner never reads schedules directly; a pending change
-- request carries what the partner needs to decide.
grant select on public.schedules to authenticated;
create policy "read own" on public.schedules for select to authenticated
  using (user_id = (select auth.uid()));
grant select on public.schedule_change_requests to authenticated;
create policy "members read" on public.schedule_change_requests for select to authenticated
  using (public.is_pair_member(pair_id));

-- minutes: own ledger; own and partner's lots and debt (partners see each other's
-- balance and expiry timeline, spec §7.11).
grant select on public.minute_ledger to authenticated;
create policy "read own" on public.minute_ledger for select to authenticated
  using (user_id = (select auth.uid()));
grant select on public.minute_lots to authenticated;
create policy "read own and partner" on public.minute_lots for select to authenticated
  using (user_id = (select auth.uid()) or public.is_partner(user_id));
grant select on public.minute_debt to authenticated;
create policy "read own and partner" on public.minute_debt for select to authenticated
  using (user_id = (select auth.uid()) or public.is_partner(user_id));
grant select on public.reset_proposals to authenticated;
create policy "members read" on public.reset_proposals for select to authenticated
  using (public.is_pair_member(pair_id));

-- unlock requests: members read, but never the code or token hashes.
grant select (id, pair_id, requester_id, minutes, reason, status, expires_at, push_sent_at,
              email_sent_at, responded_by, responded_at, created_at)
  on public.unlock_requests to authenticated;
create policy "members read" on public.unlock_requests for select to authenticated
  using (requester_id = (select auth.uid()) or public.is_pair_member(pair_id));
grant select on public.unlocks to authenticated;
create policy "read own and pair" on public.unlocks for select to authenticated
  using (user_id = (select auth.uid()) or public.is_pair_member(pair_id));
grant select on public.qr_redemptions to authenticated;
create policy "members read" on public.qr_redemptions for select to authenticated
  using (public.is_pair_member(pair_id));

-- challenges: presets are readable by every signed-in user (the library preview);
-- custom challenges by the pair's members.
grant select on public.challenges to authenticated;
create policy "presets and own pair" on public.challenges for select to authenticated
  using (pair_id is null or public.is_pair_member(pair_id));
grant select on public.challenge_completions to authenticated;
create policy "members read" on public.challenge_completions for select to authenticated
  using (completed_by = (select auth.uid()) or public.is_pair_member(pair_id));
grant select on public.kudos to authenticated;
create policy "members read" on public.kudos for select to authenticated
  using (giver_id = (select auth.uid()) or receiver_id = (select auth.uid())
         or public.is_pair_member(pair_id));
grant select on public.streaks to authenticated;
create policy "members read" on public.streaks for select to authenticated
  using (public.is_pair_member(pair_id));
grant select on public.daily_pair_status to authenticated;
create policy "members read" on public.daily_pair_status for select to authenticated
  using (public.is_pair_member(pair_id));

-- premium: own entitlements and the partner's (needed to compute pair premium).
grant select on public.entitlements to authenticated;
create policy "read own and partner" on public.entitlements for select to authenticated
  using (user_id = (select auth.uid()) or public.is_partner(user_id));
grant select on public.pair_coverage to authenticated;
create policy "members read" on public.pair_coverage for select to authenticated
  using (payer_id = (select auth.uid()) or public.is_pair_member(pair_id));

-- weekly_reports: policy is added with the premium functions (free tier sees the
-- current week only).
grant select on public.weekly_reports to authenticated;

-- No client access at all (RLS enabled, no policy, no grant):
--   pair_secrets, notifications_outbox, webhook_events, waitlist, rate_limits.
