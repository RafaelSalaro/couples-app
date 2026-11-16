// End-to-end smoke test against a deployed project: the real Edge Functions over HTTPS and
// the REST API with real user JWTs, exactly as the iPhone app calls them. Creates two
// throwaway users and deletes them at the end (through delete_account, then the admin API
// as a fallback). Run with scripts/live-smoke.sh; it never runs in the normal test suite.
import { assert, assertEquals } from "jsr:@std/assert@1.0.13";

const url = Deno.env.get("LIVE_SUPABASE_URL")!;
const anon = Deno.env.get("LIVE_ANON_KEY")!;
const service = Deno.env.get("LIVE_SERVICE_ROLE_KEY")!;
const ignore = !url || !anon || !service;

type Who = { id: string; jwt: string; email: string };

async function admin(path: string, init: RequestInit = {}) {
  return await fetch(`${url}/auth/v1/admin/${path}`, {
    ...init,
    headers: { apikey: service, authorization: `Bearer ${service}`, "content-type": "application/json", ...(init.headers ?? {}) },
  });
}

async function person(name: string): Promise<Who> {
  const email = `smoke-${name.toLowerCase()}-${crypto.randomUUID().slice(0, 8)}@example.com`;
  const password = `Smoke-${crypto.randomUUID()}`;
  const created = await (await admin("users", { method: "POST", body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { full_name: name } }) })).json();
  const token = await (await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: anon, "content-type": "application/json" }, body: JSON.stringify({ email, password }),
  })).json();
  assert(token.access_token, `sign-in failed: ${JSON.stringify(token).slice(0, 200)}`);
  return { id: created.id, jwt: token.access_token, email };
}

async function fn(name: string, who: Who | null, body: Record<string, unknown> = {}) {
  const res = await fetch(`${url}/functions/v1/${name}`, {
    method: "POST",
    headers: { apikey: anon, ...(who ? { authorization: `Bearer ${who.jwt}` } : {}), "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let json: { ok?: boolean; data?: Record<string, unknown>; error?: { code: string } } = {};
  try { json = JSON.parse(text); } catch { /* the platform's own error page */ }
  return { status: res.status, ...json, raw: text.slice(0, 200) };
}

async function rest(who: Who, path: string, init: RequestInit = {}) {
  return await fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: anon, authorization: `Bearer ${who.jwt}`, "content-type": "application/json", ...(init.headers ?? {}) },
  });
}

Deno.test({ name: "live: the app's whole main path against the deployed project", ignore, sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const rafa = await person("Rafa");
  const ana = await person("Ana");
  try {
    // Without a JWT the platform refuses before our code runs; public functions answer.
    assertEquals((await fn("unpair", null)).status, 401, "signed-in functions require a JWT");
    const waitlist = await fn("waitlist_join", null, { email: "not-an-email", source: "smoke" });
    assertEquals(waitlist.error?.code, "invalid_email", `public function answers without a JWT: ${waitlist.raw}`);

    // Pairing through the functions; the inviter reads the QR secret through RLS.
    const invite = await fn("create_invite", rafa);
    assert(invite.ok, `create_invite: ${invite.raw}`);
    const accepted = await fn("accept_invite", ana, { code: invite.data!.code });
    assert(accepted.ok, `accept_invite: ${accepted.raw}`);
    const secrets = await (await rest(rafa, "pair_secrets?select=secret")).json();
    assertEquals(secrets.length, 1, "the inviter reads the pair's QR secret");

    // The app's direct writes (each was a 403 before the security review).
    assertEquals((await rest(rafa, `user_settings?user_id=eq.${rafa.id}`, { method: "PATCH", body: JSON.stringify({ daily_max_minutes: 45 }) })).status, 204, "saving settings");
    assertEquals((await rest(rafa, "push_tokens?on_conflict=user_id,token", {
      method: "POST", headers: { Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify({ user_id: rafa.id, platform: "ios", token: `smoke-${crypto.randomUUID()}`, environment: "sandbox" }),
    })).status, 201, "registering a push token");

    // Ask → Go for it; the partner reads the request with select * (the app's query).
    const request = await fn("create_unlock_request", rafa, { minutes: 30, reason: "Smoke test" });
    assert(request.ok, `create_unlock_request: ${request.raw}`);
    const seen = await (await rest(ana, "unlock_requests?select=*")).json();
    assertEquals(seen.length, 1, "the partner sees the request");
    const answer = await fn("respond_unlock_request", ana, { request_id: request.data!.id, approve: true });
    assert(answer.ok, `respond_unlock_request: ${answer.raw}`);

    // Minutes: idempotent by client_event_id, and the balance reads back through the view.
    const event = crypto.randomUUID();
    const first = await fn("spend_minutes_unlock", ana, { minutes: 15, client_event_id: event });
    const again = await fn("spend_minutes_unlock", ana, { minutes: 15, client_event_id: event });
    assert(first.ok && again.ok, `spend: ${first.raw} / ${again.raw}`);
    assertEquals(first.data!.id, again.data!.id, "a retried spend is the same unlock");
    const balances = await (await rest(ana, `balances?select=balance&user_id=eq.${ana.id}`)).json();
    assertEquals(balances[0]?.balance, 15, "30 starting minutes, 15 spent once");
    assertEquals((await fn("give_kudos", ana, { minutes: 10, message: "Thanks" })).error?.code, "premium_required");

    // Emergency (P14, P26): a session for the allowance; ending early borrows only the minute used.
    const emergency = await fn("emergency_unlock", ana, { client_event_id: crypto.randomUUID() });
    assert(emergency.ok && emergency.data!.minutes === 15, `emergency_unlock: ${emergency.raw}`);
    const ended = await fn("end_unlock_early", ana, { unlock_id: emergency.data!.id, client_event_id: crypto.randomUUID() });
    assert(ended.ok && ended.data!.minutes_used === 1, `end_unlock_early: ${ended.raw}`);
    const afterEmergency = await (await rest(ana, `balances?select=balance&user_id=eq.${ana.id}`)).json();
    assertEquals(afterEmergency[0]?.balance, 14, "15 left, 1 borrowed for the minute used");
    const allowance = await (await rest(ana, `user_settings?select=emergency_allowance_minutes&user_id=eq.${ana.id}`)).json();
    assertEquals(allowance[0]?.emergency_allowance_minutes, 15, "the default allowance reads back");

    // Unpair and delete both accounts through the app's own calls.
    assert((await fn("unpair", ana)).ok, "unpair");
    assert((await fn("delete_account", rafa)).ok, "delete_account");
    assert((await fn("delete_account", ana)).ok, "delete_account");
    assertEquals((await admin(`users/${rafa.id}`)).status, 404, "the auth user is gone");
  } finally {
    // Fallback cleanup if an assertion stopped the test early.
    for (const who of [rafa, ana]) await (await admin(`users/${who.id}`, { method: "DELETE" })).body?.cancel();
  }
}});
