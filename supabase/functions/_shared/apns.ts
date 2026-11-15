// APNs with token-based auth (docs/04: push straight from Edge Functions).
// Secrets: APNS_KEY (the .p8 contents), APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC (bundle id).
import type { PushMessage } from "./messages.ts";

export interface ApnsConfig {
  keyPem: string;
  keyId: string;
  teamId: string;
  topic: string;
}

export type ApnsResult = { ok: true } | { ok: false; status: number; reason: string; /** token is dead: remove it */ unregistered: boolean };

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const encodeJson = (value: unknown) => b64url(new TextEncoder().encode(JSON.stringify(value)));

let cached: { jwt: string; at: number; keyId: string } | null = null;

/** The provider JWT (ES256). Apple accepts one for up to an hour; we renew every 50 minutes. */
export async function providerToken(config: ApnsConfig, nowSeconds = Math.floor(Date.now() / 1000)): Promise<string> {
  if (cached && cached.keyId === config.keyId && nowSeconds - cached.at < 3000) return cached.jwt;
  const der = Uint8Array.from(atob(config.keyPem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const unsigned = `${encodeJson({ alg: "ES256", kid: config.keyId })}.${encodeJson({ iss: config.teamId, iat: nowSeconds })}`;
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned)));
  const jwt = `${unsigned}.${b64url(signature)}`;
  cached = { jwt, at: nowSeconds, keyId: config.keyId };
  return jwt;
}

/** The APNs request body. Custom keys are strings, which is what the app reads. */
export function apnsPayload(message: PushMessage, custom: Record<string, string>): Record<string, unknown> {
  if (message.silent) return { aps: { "content-available": 1 }, ...custom };
  const aps: Record<string, unknown> = {
    alert: { title: message.title, body: message.body },
    sound: "default",
    "interruption-level": message.timeSensitive ? "time-sensitive" : "active",
  };
  if (message.category) aps.category = message.category;
  return { aps, ...custom, ...(message.link ? { link: message.link } : {}) };
}

export async function sendApns(
  config: ApnsConfig, token: string, environment: "sandbox" | "production", body: Record<string, unknown>,
  fetcher: typeof fetch = fetch,
): Promise<ApnsResult> {
  const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const silent = (body.aps as Record<string, unknown>)["content-available"] === 1;
  const res = await fetcher(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken(config)}`,
      "apns-topic": config.topic,
      "apns-push-type": silent ? "background" : "alert",
      "apns-priority": silent ? "5" : "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (res.ok) return { ok: true };
  const reason = ((await res.json().catch(() => ({}))) as { reason?: string }).reason ?? `HTTP ${res.status}`;
  return { ok: false, status: res.status, reason, unregistered: res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered" };
}
