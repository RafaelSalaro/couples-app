// End-to-end tests of the Edge Function handlers against the local Supabase stack: real
// users, real JWTs, the real SQL functions. Skipped unless SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are set (scripts/functions-test.sh sets them from `supabase status`).
import { assert, assertEquals } from "jsr:@std/assert@1.0.13";
import { createClient } from "jsr:@supabase/supabase-js@2.49.4";
import { apiHandler } from "../_shared/api.ts";
import { adminClient, liveDeps } from "../_shared/supabase.ts";

const url = Deno.env.get("SUPABASE_URL");
const ignore = !url || !Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || !Deno.env.get("SUPABASE_ANON_KEY");

async function person(name: string): Promise<{ id: string; jwt: string }> {
  const email = `${name.toLowerCase()}-${crypto.randomUUID().slice(0, 8)}@example.com`;
  const password = crypto.randomUUID();
  const { data, error } = await adminClient().auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: name } });
  if (error) throw error;
  const anon = createClient(url!, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } });
  const { data: session, error: signInError } = await anon.auth.signInWithPassword({ email, password });
  if (signInError) throw signInError;
  return { id: data.user.id, jwt: session.session!.access_token };
}

async function call(name: string, who: { jwt: string }, body: Record<string, unknown> = {}) {
  const res = await apiHandler(name, liveDeps())(new Request(`http://local/${name}`, {
    method: "POST", headers: { authorization: `Bearer ${who.jwt}`, "content-type": "application/json" }, body: JSON.stringify(body),
  }));
  return { status: res.status, ...(await res.json()) as { ok: boolean; data?: Record<string, unknown>; error?: { code: string } } };
}

Deno.test({ name: "pairing, asking, answering and spending through the real functions", ignore, sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const rafa = await person("Rafa");
  const ana = await person("Ana");

  const invite = await call("create_invite", rafa);
  assert(invite.ok, JSON.stringify(invite));
  assert(String(invite.data!.link).includes("/i/"));
  const accepted = await call("accept_invite", ana, { code: invite.data!.code });
  assert(accepted.ok, JSON.stringify(accepted));

  // The inviter reads the QR secret through RLS, as the app does.
  const rafaClient = createClient(url!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { authorization: `Bearer ${rafa.jwt}` } }, auth: { persistSession: false },
  });
  const { data: secrets } = await rafaClient.from("pair_secrets").select("secret");
  assertEquals(secrets?.length, 1);

  // Ask → Go for it → an unlock for the requester.
  const request = await call("create_unlock_request", rafa, { minutes: 30, reason: "Reply to a client" });
  assert(request.ok, JSON.stringify(request));
  assertEquals((await call("respond_unlock_request", rafa, { request_id: request.data!.id, approve: true })).error?.code, "not_partner");
  const answer = await call("respond_unlock_request", ana, { request_id: request.data!.id, approve: true });
  assert(answer.ok, JSON.stringify(answer));

  // Minutes unlock: idempotent by client_event_id; the second spend is a replay, not a second spend.
  const event = crypto.randomUUID();
  const first = await call("spend_minutes_unlock", ana, { minutes: 15, client_event_id: event });
  const again = await call("spend_minutes_unlock", ana, { minutes: 15, client_event_id: event });
  assert(first.ok && again.ok, JSON.stringify([first, again]));
  assertEquals(first.data!.id, again.data!.id);
  const { data: balance } = await adminClient().rpc("balance_of", { p_user: ana.id });
  assertEquals(balance, 15, "30 starting minutes, 15 spent once");

  // Errors arrive as codes the app knows.
  assertEquals((await call("spend_minutes_unlock", ana, { minutes: 60, client_event_id: crypto.randomUUID() })).error?.code, "insufficient");
  assertEquals((await call("give_kudos", ana, { minutes: 10, message: "Thanks" })).error?.code, "premium_required");

  // Emergency (P14, P26): a session for the allowance; ending early borrows only what was used.
  const emergency = await call("emergency_unlock", ana, { client_event_id: crypto.randomUUID() });
  assert(emergency.ok && emergency.data!.minutes === 15, JSON.stringify(emergency));
  const ended = await call("end_unlock_early", ana, { unlock_id: emergency.data!.id });
  assert(ended.ok && ended.data!.minutes_used === 1, JSON.stringify(ended));
  const { data: after } = await adminClient().rpc("balance_of", { p_user: ana.id });
  assertEquals(after, 14, "15 left, 1 borrowed for the minute used");
  const { data: status } = await adminClient().rpc("emergency_status", { p_user: ana.id });
  assertEquals((status as { remaining: number }).remaining, 14);
  assertEquals((await call("spend_minutes_unlock", ana, { minutes: "lots" })).error?.code, "invalid_input");

  // Unpair, then delete both accounts (also cleans up).
  const unpaired = await call("unpair", ana);
  assert(unpaired.ok, JSON.stringify(unpaired));
  assert((await call("delete_account", rafa)).ok);
  assert((await call("delete_account", ana)).ok);
  const { data: gone } = await adminClient().auth.admin.getUserById(rafa.id);
  assertEquals(gone.user, null);
}});

Deno.test({ name: "a request without a valid JWT is refused", ignore, sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const res = await call("unpair", { jwt: "not-a-jwt" });
  assertEquals([res.status, res.error?.code], [401, "unauthorized"]);
}});
