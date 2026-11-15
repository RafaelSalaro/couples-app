// RevenueCat webhook → entitlements (docs/03 §12, WP-12 backend side). RevenueCat sends a
// static Authorization header configured in its dashboard (secret REVENUECAT_WEBHOOK_AUTH).
// The app logs in to RevenueCat with our user id (lowercased uuid), so app_user_id is ours.

export interface EntitlementChange {
  user_id: string;
  product_id: string;
  kind: "trial" | "subscription" | "lifetime";
  active: boolean;
  expires_at: string | null;
  store: "app_store" | "play_store";
  event_at: string;
}

export interface RevenueCatEvent {
  id: string;
  type: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  product_id?: string;
  period_type?: string;
  expiration_at_ms?: number | null;
  event_timestamp_ms?: number;
  store?: string;
  transferred_from?: string[];
  transferred_to?: string[];
  environment?: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Our user id among the ids RevenueCat knows for the customer (anonymous ids are skipped). */
function ourUser(event: RevenueCatEvent): string | null {
  const ids = [event.app_user_id, event.original_app_user_id, ...(event.aliases ?? [])];
  return ids.find((id): id is string => typeof id === "string" && UUID.test(id))?.toLowerCase() ?? null;
}

/** Turns one webhook event into the entitlement rows to write. Unknown or test events give none. */
export function entitlementChanges(event: RevenueCatEvent, now = Date.now()): EntitlementChange[] {
  const at = new Date(event.event_timestamp_ms ?? now).toISOString();
  const store = event.store === "PLAY_STORE" ? "play_store" : "app_store";
  const expires = event.expiration_at_ms ? new Date(event.expiration_at_ms).toISOString() : null;

  if (event.type === "TRANSFER") {
    // The purchase moved to another of our users: the old owner loses it now; RevenueCat
    // then sends the new owner's events.
    return (event.transferred_from ?? []).filter((id) => UUID.test(id)).map((id) => ({
      user_id: id.toLowerCase(), product_id: event.product_id ?? "transferred", kind: "subscription",
      active: false, expires_at: at, store, event_at: at,
    }));
  }

  const user = ourUser(event);
  if (!user || !event.product_id) return [];
  const lifetime = event.type === "NON_RENEWING_PURCHASE" || event.product_id.toLowerCase().includes("lifetime");
  const kind = lifetime ? "lifetime" : event.period_type === "TRIAL" ? "trial" : "subscription";
  let active: boolean;
  switch (event.type) {
    case "INITIAL_PURCHASE": case "RENEWAL": case "PRODUCT_CHANGE": case "UNCANCELLATION":
    case "NON_RENEWING_PURCHASE": case "SUBSCRIPTION_EXTENDED": case "TEMPORARY_ENTITLEMENT_GRANT":
      active = true; break;
    // Cancelling keeps premium until the period ends; a billing issue keeps it through the grace period.
    case "CANCELLATION": case "BILLING_ISSUE": case "SUBSCRIPTION_PAUSED":
      active = expires === null ? lifetime : Date.parse(expires) > now; break;
    case "EXPIRATION":
      active = false; break;
    default:
      return []; // TEST and anything new: nothing to change
  }
  return [{ user_id: user, product_id: event.product_id, kind, active, expires_at: lifetime ? null : expires, store, event_at: at }];
}

/** Constant-time comparison of the Authorization header with the configured secret. */
export function authorized(header: string | null, secret: string): boolean {
  if (!header || !secret) return false;
  const a = new TextEncoder().encode(header.replace(/^Bearer\s+/i, ""));
  const b = new TextEncoder().encode(secret.replace(/^Bearer\s+/i, ""));
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
