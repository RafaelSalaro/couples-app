// RevenueCat → entitlements → pair premium (docs/05 §3, WP-12 backend side).
// Idempotent: each event id is applied once (webhook_events); older events never undo newer ones.
import { fail, json } from "../_shared/http.ts";
import { authorized, entitlementChanges, type RevenueCatEvent } from "../_shared/revenuecat.ts";
import { adminClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail("method_not_allowed", 405);
  if (!authorized(req.headers.get("authorization"), Deno.env.get("REVENUECAT_WEBHOOK_AUTH") ?? "")) return fail("bad_signature", 401);
  const body = await req.json().catch(() => null) as { event?: RevenueCatEvent } | null;
  const event = body?.event;
  if (!event?.id || !event.type) return fail("invalid_input", 400);

  const db = adminClient();
  const { error: seen } = await db.from("webhook_events").insert({ provider: "revenuecat", event_id: event.id });
  if (seen) {
    if (seen.code === "23505") return json({ ok: true, data: { duplicate: true } });
    return fail("server_error", 500);
  }
  for (const change of entitlementChanges(event)) {
    const { error } = await db.rpc("api_apply_entitlement", {
      p_user: change.user_id, p_product: change.product_id, p_kind: change.kind, p_active: change.active,
      p_expires_at: change.expires_at, p_store: change.store, p_event_at: change.event_at,
    });
    // A purchase for a user we do not know (deleted account): nothing to apply.
    if (error && !(error.code === "CAERR" && error.message === "not_found")) {
      // Let RevenueCat retry: forget the event id so the retry is applied.
      await db.from("webhook_events").delete().eq("provider", "revenuecat").eq("event_id", event.id);
      return fail("server_error", 500);
    }
  }
  return json({ ok: true, data: null });
});
