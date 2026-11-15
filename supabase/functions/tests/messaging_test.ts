// Unit tests: outbox delivery, push payloads, APNs auth, RevenueCat mapping, copy.
import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1.0.13";
import { apnsPayload, providerToken, sendApns } from "../_shared/apns.ts";
import { pushFor, unlockRequestEmail } from "../_shared/messages.ts";
import { customKeys, maxAttempts, type OutboxDeps, type OutboxItem, processOutbox } from "../_shared/outbox.ts";
import { authorized, entitlementChanges } from "../_shared/revenuecat.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const REQ = "22222222-2222-4222-8222-222222222222";

function item(over: Partial<OutboxItem>): OutboxItem {
  return { id: "o1", kind: "unlock_request", channel: "push", payload: { request_id: REQ, minutes: 30 }, attempts: 1,
           email: "ana@example.com", from_name: "Rafa", tokens: [{ token: "t1", environment: "production" }], ...over };
}

function deps(items: OutboxItem[], over: Partial<OutboxDeps> = {}) {
  const log = { finished: [] as [string, string][], pushes: [] as unknown[], emails: [] as unknown[], removed: [] as string[] };
  const d: OutboxDeps = {
    claim: () => Promise.resolve(items),
    finish: (id, outcome) => { log.finished.push([id, outcome]); return Promise.resolve(); },
    issueUnlockEmailSecrets: () => Promise.resolve({ code: "482913", approve_token: "tok", minutes: 30, reason: "Reply to a client" }),
    removeToken: (t) => { log.removed.push(t); return Promise.resolve(); },
    push: (token, env, message, custom) => { log.pushes.push({ token, env, message, custom }); return Promise.resolve({ ok: true }); },
    email: (to, message) => { log.emails.push({ to, message }); return Promise.resolve({ ok: true }); },
    appName: "Couples App", urlScheme: "couplesapp", domain: "example.com", functionsUrl: "https://x.supabase.co/functions/v1",
    ...over,
  };
  return { d, log };
}

Deno.test("an unlock request push is actionable and time-sensitive, with the reason", () => {
  const push = pushFor("unlock_request", { request_id: REQ, minutes: 30, reason: "Reply to a client" }, "Ana", "couplesapp")!;
  assertEquals(push.body, "Ana asks for 30 min · “Reply to a client”");
  assertEquals([push.category, push.timeSensitive, push.link], ["UNLOCK_REQUEST", true, `couplesapp://request/${REQ}`]);
  const body = apnsPayload(push, customKeys("unlock_request", { request_id: REQ }));
  assertEquals((body.aps as Record<string, unknown>)["interruption-level"], "time-sensitive");
  assertEquals((body.aps as Record<string, unknown>).category, "UNLOCK_REQUEST");
  assertEquals(body.request_id, REQ);
});

Deno.test("schedule-change pushes carry change_id, which the app's buttons read", () => {
  assertEquals(customKeys("schedule_change_requested", { request_id: REQ }), { kind: "schedule_change_requested", change_id: REQ });
});

Deno.test("copy never scolds: let's wait, expiry and partner notes are gentle", () => {
  const words = ["denied", "rejected", "blocked", "failed", "violation"];
  for (const kind of ["unlock_declined", "unlock_expired", "emergency_used", "unpaired", "protected_time_off", "reset_declined", "schedule_change_declined"]) {
    const push = pushFor(kind, {}, "Ana", "couplesapp")!;
    for (const word of words) assert(!`${push.title} ${push.body}`.toLowerCase().includes(word), `${kind} says ${word}`);
  }
  assertEquals(pushFor("unlock_declined", {}, "Ana", "couplesapp")!.body, "Ana says let's wait — maybe later?");
  assertEquals(pushFor("unlock_expired", {}, "Ana", "couplesapp")!.body, "You can try again or use your minutes.");
  assertEquals(pushFor("minutes_expiring", { minutes: 15 }, "Ana", "couplesapp")!.body, "15 of your minutes expire tomorrow — maybe a walk together?");
});

Deno.test("a rotated QR secret is a silent push", () => {
  const body = apnsPayload(pushFor("qr_secret_rotated", {}, "Ana", "couplesapp")!, { kind: "qr_secret_rotated" });
  assertEquals(body.aps, { "content-available": 1 });
});

Deno.test("the outbox sends to every phone and removes dead tokens", async () => {
  const { d, log } = deps([item({ tokens: [{ token: "alive", environment: "production" }, { token: "dead", environment: "sandbox" }] })], {
    push: (token) => Promise.resolve(token === "dead" ? { ok: false, unregistered: true } : { ok: true }),
  });
  assertEquals(await processOutbox(d), { sent: 1, retry: 0, failed: 0 });
  assertEquals(log.removed, ["dead"]);
});

Deno.test("a temporary APNs failure is retried, then given up after the last attempt", async () => {
  const flaky = { push: () => Promise.resolve({ ok: false, unregistered: false }) };
  assertEquals((await processOutbox(deps([item({ attempts: 1 })], flaky).d)).retry, 1);
  assertEquals((await processOutbox(deps([item({ attempts: maxAttempts })], flaky).d)).failed, 1);
});

Deno.test("no phone registered: the push row is done, nothing is sent", async () => {
  const { d, log } = deps([item({ tokens: [] })]);
  assertEquals((await processOutbox(d)).sent, 1);
  assertEquals(log.pushes.length, 0);
});

Deno.test("the fallback email carries the approve link and the code, issued at send time", async () => {
  const { d, log } = deps([item({ kind: "unlock_request_email", channel: "email" })]);
  await processOutbox(d);
  const { to, message } = log.emails[0] as { to: string; message: { subject: string; text: string; html: string } };
  assertEquals(to, "ana@example.com");
  assertEquals(message.subject, "Rafa asks for 30 minutes");
  assertMatch(message.text, /https:\/\/example\.com\/approve\/tok/);
  assertMatch(message.text, /482913/);
});

Deno.test("no fallback email once the request was answered", async () => {
  const { d, log } = deps([item({ kind: "unlock_request_email", channel: "email" })], { issueUnlockEmailSecrets: () => Promise.resolve(null) });
  assertEquals((await processOutbox(d)).sent, 1);
  assertEquals(log.emails.length, 0);
});

Deno.test("email content is escaped", () => {
  const email = unlockRequestEmail("App", "<b>Rafa</b>", 30, null, "123456", "https://example.com/approve/x");
  assert(!email.html.includes("<b>Rafa</b>"));
  assert(email.html.includes("&lt;b&gt;Rafa&lt;/b&gt;"));
});

Deno.test("waitlist confirmation goes to the address in the row", async () => {
  const { d, log } = deps([item({ kind: "waitlist_confirm", channel: "email", email: null, payload: { email: "new@example.com", token: "abc" } })]);
  await processOutbox(d);
  const { to, message } = log.emails[0] as { to: string; message: { text: string } };
  assertEquals(to, "new@example.com");
  assertMatch(message.text, /waitlist_confirm\?token=abc/);
});

Deno.test("APNs: ES256 provider token, alert headers, 410 means unregistered", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
  const config = { keyPem: pem, keyId: "KEY123", teamId: "TEAM123", topic: "com.example.couplesapp" };
  const jwt = await providerToken(config, 1_800_000_000);
  const [header, claims, signature] = jwt.split(".");
  const decode = (s: string) => JSON.parse(atob(s.replace(/-/g, "+").replace(/_/g, "/")));
  assertEquals(decode(header), { alg: "ES256", kid: "KEY123" });
  assertEquals(decode(claims), { iss: "TEAM123", iat: 1_800_000_000 });
  const sig = Uint8Array.from(atob(signature.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
  assert(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, sig, new TextEncoder().encode(`${header}.${claims}`)));

  let seen: Request | null = null;
  const fake = ((input: string | URL | Request, init?: RequestInit) => {
    seen = new Request(input, init);
    return Promise.resolve(new Response(JSON.stringify({ reason: "Unregistered" }), { status: 410 }));
  }) as typeof fetch;
  const result = await sendApns(config, "abc", "sandbox", apnsPayload(pushFor("kudos_received", { minutes: 10 }, "Ana", "couplesapp")!, {}), fake);
  assertEquals(result, { ok: false, status: 410, reason: "Unregistered", unregistered: true });
  assertEquals(seen!.url, "https://api.sandbox.push.apple.com/3/device/abc");
  assertEquals([seen!.headers.get("apns-topic"), seen!.headers.get("apns-push-type"), seen!.headers.get("apns-priority")], ["com.example.couplesapp", "alert", "10"]);
});

Deno.test("RevenueCat: purchase, trial, lifetime, cancellation and expiry", () => {
  const now = Date.parse("2026-11-15T12:00:00Z");
  const base = { id: "e", app_user_id: USER.toUpperCase(), product_id: "yearly", event_timestamp_ms: now, store: "APP_STORE" };
  const later = Date.parse("2027-11-15T12:00:00Z");
  assertEquals(entitlementChanges({ ...base, type: "INITIAL_PURCHASE", period_type: "TRIAL", expiration_at_ms: Date.parse("2026-11-29T12:00:00Z") }, now)[0],
    { user_id: USER, product_id: "yearly", kind: "trial", active: true, expires_at: "2026-11-29T12:00:00.000Z", store: "app_store", event_at: "2026-11-15T12:00:00.000Z" });
  assertEquals(entitlementChanges({ ...base, type: "RENEWAL", period_type: "NORMAL", expiration_at_ms: later }, now)[0].kind, "subscription");
  assertEquals(entitlementChanges({ ...base, type: "CANCELLATION", expiration_at_ms: later }, now)[0].active, true, "cancelled keeps premium to the end");
  assertEquals(entitlementChanges({ ...base, type: "EXPIRATION", expiration_at_ms: now }, now)[0].active, false);
  const lifetime = entitlementChanges({ ...base, type: "NON_RENEWING_PURCHASE", product_id: "lifetime" }, now)[0];
  assertEquals([lifetime.kind, lifetime.active, lifetime.expires_at], ["lifetime", true, null]);
});

Deno.test("RevenueCat: anonymous ids, test events and transfers", () => {
  assertEquals(entitlementChanges({ id: "e", type: "INITIAL_PURCHASE", app_user_id: "$RCAnonymousID:abc", product_id: "yearly" }), []);
  assertEquals(entitlementChanges({ id: "e", type: "INITIAL_PURCHASE", app_user_id: "$RCAnonymousID:abc", aliases: [USER], product_id: "yearly" })[0].user_id, USER);
  assertEquals(entitlementChanges({ id: "e", type: "TEST", app_user_id: USER, product_id: "yearly" }), []);
  const moved = entitlementChanges({ id: "e", type: "TRANSFER", transferred_from: [USER], transferred_to: ["x"], product_id: "yearly" });
  assertEquals([moved.length, moved[0].user_id, moved[0].active], [1, USER, false]);
});

Deno.test("shared-secret checks are exact", () => {
  assert(authorized("Bearer s3cret", "s3cret"));
  assert(authorized("s3cret", "s3cret"));
  assert(!authorized("s3cre", "s3cret"));
  assert(!authorized(null, "s3cret"));
  assert(!authorized("anything", ""));
});
