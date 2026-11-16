// Unit tests of the API layer with fake dependencies (no database).
// Run: deno test --allow-env supabase/functions/tests/api_test.ts
import { assertEquals } from "jsr:@std/assert@1.0.13";
import { apiHandler, type Deps, endpoints } from "../_shared/api.ts";
import { ApiError, corsHeaders, fromDatabaseError } from "../_shared/http.ts";

const ME = "11111111-1111-4111-8111-111111111111";

function fakeDeps(result: { data?: unknown; error?: { code?: string; message?: string } | null } = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const deleted: string[] = [];
  const deps: Deps = {
    userId: (req) => req.headers.get("authorization") === "Bearer good" ? Promise.resolve(ME) : Promise.reject(new ApiError("unauthorized", 401)),
    rpc: (fn, args) => {
      calls.push({ fn, args });
      return Promise.resolve({ data: (result.data ?? null) as never, error: result.error ?? null });
    },
    deleteAuthUser: (id) => { deleted.push(id); return Promise.resolve(); },
    appDomain: "example.com",
  };
  return { deps, calls, deleted };
}

const post = (body: unknown, auth = "Bearer good") =>
  new Request("http://localhost/fn", { method: "POST", headers: { authorization: auth, "content-type": "application/json" }, body: JSON.stringify(body) });

Deno.test("every function of doc 05 §3 the app calls has an endpoint", () => {
  const expected = [
    "create_invite", "revoke_invite", "accept_invite", "unpair", "rotate_qr_secret", "create_unlock_request",
    "respond_unlock_request", "redeem_accountability_code", "spend_minutes_unlock", "emergency_unlock", "sync_qr_unlocks",
    "complete_challenge", "confirm_completion", "create_custom_challenge", "respond_challenge_value", "give_kudos",
    "propose_reset", "respond_reset", "propose_schedule_change", "respond_schedule_change", "export_my_data", "delete_account",
    "end_unlock_early",
  ];
  assertEquals(Object.keys(endpoints).sort(), expected.sort());
  for (const name of expected) assertEquals(endpoints[name].rpc, `api_${name}`);
});

Deno.test("no valid JWT: unauthorized, and nothing reaches the database", async () => {
  const { deps, calls } = fakeDeps();
  const res = await apiHandler("unpair", deps)(post({}, "Bearer nope"));
  assertEquals(res.status, 401);
  assertEquals(await res.json(), { ok: false, error: { code: "unauthorized", message: "unauthorized" } });
  assertEquals(calls.length, 0);
});

Deno.test("the caller's id comes from the JWT, never from the body", async () => {
  const { deps, calls } = fakeDeps({ data: { id: "x" } });
  await apiHandler("give_kudos", deps)(post({ minutes: 10, message: "Thanks", receiver_id: "22222222-2222-4222-8222-222222222222", p_user: "evil" }));
  assertEquals(calls[0], { fn: "api_give_kudos", args: { p_user: ME, p_minutes: 10, p_message: "Thanks", p_challenge: null } });
});

Deno.test("bad input is a calm invalid_input before any database call", async () => {
  const { deps, calls } = fakeDeps();
  for (const body of [{ minutes: "30" }, { minutes: 30.5 }, {}]) {
    const res = await apiHandler("spend_minutes_unlock", deps)(post(body));
    assertEquals((await res.json()).error.code, "invalid_input");
  }
  const res = await apiHandler("respond_unlock_request", deps)(post({ request_id: "not-a-uuid", approve: true }));
  assertEquals((await res.json()).error.code, "invalid_input");
  assertEquals(calls.length, 0);
});

Deno.test("SQL business errors become error codes", async () => {
  const { deps } = fakeDeps({ error: { code: "CAERR", message: "over_daily_max" } });
  const res = await apiHandler("spend_minutes_unlock", deps)(post({ minutes: 30, client_event_id: ME }));
  assertEquals(res.status, 409);
  assertEquals(await res.json(), { ok: false, error: { code: "over_daily_max", message: "over_daily_max" } });
});

Deno.test("outcomes returned as {error} (expired, wrong code) are errors for the app", async () => {
  const { deps } = fakeDeps({ data: { error: "expired" } });
  const res = await apiHandler("respond_unlock_request", deps)(post({ request_id: ME, approve: true }));
  assertEquals((await res.json()).error.code, "expired");
  const tooMany = fakeDeps({ data: { error: "too_many_attempts" } });
  const res2 = await apiHandler("redeem_accountability_code", tooMany.deps)(post({ request_id: ME, code: "123456" }));
  assertEquals(res2.status, 429);
});

Deno.test("unknown database failures do not leak details", async () => {
  const error = fromDatabaseError({ code: "23505", message: "duplicate key value violates unique constraint" });
  assertEquals([error.code, error.status], ["server_error", 500]);
  const { deps } = fakeDeps({ error: { code: "XX000", message: "internal detail" } });
  const res = await apiHandler("unpair", deps)(post({}));
  assertEquals(await res.json(), { ok: false, error: { code: "server_error", message: "server_error" } });
});

Deno.test("results are shaped as the app expects", async () => {
  const invite = fakeDeps({ data: { id: "i", code: "ABC234", link_token: "tok", expires_at: "2026-11-18T10:00:00Z" } });
  const res = await apiHandler("create_invite", invite.deps)(post({}));
  assertEquals((await res.json()).data, { id: "i", code: "ABC234", link: "https://example.com/i/tok", expires_at: "2026-11-18T10:00:00Z" });

  const unlock = fakeDeps({ data: { unlock: { id: "u", minutes: 15 }, balance: -15 } });
  const res2 = await apiHandler("emergency_unlock", unlock.deps)(post({ client_event_id: ME }));
  assertEquals((await res2.json()).data, { id: "u", minutes: 15 });
});

Deno.test("accept_invite takes the code or the link token", async () => {
  const { deps, calls } = fakeDeps({ data: {} });
  await apiHandler("accept_invite", deps)(post({ code: "abc234" }));
  await apiHandler("accept_invite", deps)(post({ link_token: "a-long-link-token" }));
  assertEquals(calls.map((c) => c.args.p_code_or_token), ["abc234", "a-long-link-token"]);
});

Deno.test("deleting an account removes the auth user only after the data is gone", async () => {
  const ok = fakeDeps({ data: { deleted: ME } });
  await apiHandler("delete_account", ok.deps)(post({}));
  assertEquals(ok.deleted, [ME]);
  const failed = fakeDeps({ error: { code: "XX000", message: "boom" } });
  await apiHandler("delete_account", failed.deps)(post({}));
  assertEquals(failed.deleted, []);
});

Deno.test("only POST; CORS preflight answers for allowed origins only", async () => {
  const { deps } = fakeDeps();
  assertEquals((await apiHandler("unpair", deps)(new Request("http://x", { method: "GET" }))).status, 405);
  assertEquals(corsHeaders("https://example.com", ["https://example.com"])["access-control-allow-origin"], "https://example.com");
  assertEquals(corsHeaders("https://evil.test", ["https://example.com"])["access-control-allow-origin"], undefined);
});

Deno.test("end_unlock_early takes the unlock id and returns the ended unlock", async () => {
  const UNLOCK = "33333333-3333-4333-8333-333333333333";
  const { deps, calls } = fakeDeps({ data: { unlock: { id: UNLOCK, minutes_used: 2 }, refunded: 0, emergency: { remaining: 13 } } });
  const res = await apiHandler("end_unlock_early", deps)(post({ unlock_id: UNLOCK, client_event_id: ME }));
  assertEquals(calls[0], { fn: "api_end_unlock_early", args: { p_user: ME, p_unlock: UNLOCK } });
  assertEquals((await res.json()).data, { id: UNLOCK, minutes_used: 2 });
  const missing = await apiHandler("end_unlock_early", deps)(post({}));
  assertEquals((await missing.json()).error.code, "invalid_input");
});
