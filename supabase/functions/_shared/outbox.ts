// Delivers queued notifications (notifications_outbox). Run every minute by pg_cron through
// the `send_notifications` function. SQL decides who gets what and respects muted categories
// (enqueue_notification); this file only renders and delivers.
import { pushFor, unlockRequestEmail, waitlistEmail, weeklyReportEmail, type EmailMessage, type PushMessage } from "./messages.ts";

/** One claimed outbox row, with what the sender needs to address it (from `claim_outbox`). */
export interface OutboxItem {
  id: string;
  kind: string;
  channel: "push" | "email";
  payload: Record<string, unknown>;
  attempts: number;
  /** The recipient's email (auth), for email rows. */
  email: string | null;
  /** The display name of `payload.from_user_id`, or the recipient's partner. */
  from_name: string | null;
  tokens: { token: string; environment: "sandbox" | "production" }[];
}

export interface OutboxDeps {
  claim(limit: number): Promise<OutboxItem[]>;
  finish(id: string, outcome: "sent" | "retry" | "failed"): Promise<void>;
  issueUnlockEmailSecrets(requestId: string): Promise<{ code: string; approve_token: string; minutes: number; reason: string | null } | null>;
  removeToken(token: string): Promise<void>;
  push(token: string, environment: "sandbox" | "production", message: PushMessage, custom: Record<string, string>): Promise<{ ok: boolean; unregistered?: boolean }>;
  email(to: string, message: EmailMessage): Promise<{ ok: boolean }>;
  appName: string;
  urlScheme: string;
  /** The website's domain, for approve and confirm links. */
  domain: string;
  /** Base URL of the Edge Functions, for the waitlist confirm link. */
  functionsUrl: string;
}

export const maxAttempts = 5;

/** String custom keys the app reads from a push (PushIntent.parse): ids, link and kind. */
export function customKeys(kind: string, payload: Record<string, unknown>): Record<string, string> {
  const keys: Record<string, string> = { kind };
  for (const key of ["request_id", "completion_id", "challenge_id", "kudos_id", "proposal_id", "pair_id"]) {
    if (typeof payload[key] === "string") keys[key] = payload[key] as string;
  }
  // The schedule-change actions read the request id as change_id.
  if (kind.startsWith("schedule_change") && keys.request_id) {
    keys.change_id = keys.request_id;
    delete keys.request_id;
  }
  return keys;
}

async function deliver(item: OutboxItem, deps: OutboxDeps): Promise<"sent" | "retry" | "failed"> {
  const from = item.from_name || "Your partner";
  if (item.channel === "push") {
    const message = pushFor(item.kind, item.payload, from, deps.urlScheme);
    if (!message || item.tokens.length === 0) return "sent"; // nothing to show, or no phone to show it on
    let delivered = false;
    let retryable = false;
    for (const { token, environment } of item.tokens) {
      const result = await deps.push(token, environment, message, customKeys(item.kind, item.payload));
      if (result.ok) delivered = true;
      else if (result.unregistered) await deps.removeToken(token);
      else retryable = true;
    }
    return delivered || !retryable ? "sent" : "retry";
  }

  let message: EmailMessage | null = null;
  let to = item.email;
  switch (item.kind) {
    case "unlock_request_email": {
      const secrets = await deps.issueUnlockEmailSecrets(String(item.payload.request_id));
      if (!secrets) return "sent"; // answered, expired or already emailed: no email needed
      message = unlockRequestEmail(deps.appName, from, secrets.minutes, secrets.reason, secrets.code, `https://${deps.domain}/approve/${secrets.approve_token}`);
      break;
    }
    case "waitlist_confirm":
      to = typeof item.payload.email === "string" ? item.payload.email : null;
      message = waitlistEmail(deps.appName, `${deps.functionsUrl}/waitlist_confirm?token=${encodeURIComponent(String(item.payload.token))}`);
      break;
    case "weekly_report_email":
      message = weeklyReportEmail(deps.appName, from, {
        earned: Number(item.payload.earned ?? 0), together: Number(item.payload.together ?? 0), streak: Number(item.payload.streak ?? 0),
      }, `${deps.urlScheme}://report`);
      break;
  }
  if (!message || !to) return "failed";
  return (await deps.email(to, message)).ok ? "sent" : "retry";
}

/** Sends up to `limit` due notifications. Returns how each ended. */
export async function processOutbox(deps: OutboxDeps, limit = 100): Promise<Record<string, number>> {
  const counts: Record<string, number> = { sent: 0, retry: 0, failed: 0 };
  for (const item of await deps.claim(limit)) {
    let outcome: "sent" | "retry" | "failed";
    try {
      outcome = await deliver(item, deps);
    } catch (error) {
      console.error("outbox delivery failed", item.id, error);
      outcome = "retry";
    }
    if (outcome === "retry" && item.attempts >= maxAttempts) outcome = "failed";
    await deps.finish(item.id, outcome);
    counts[outcome]++;
  }
  return counts;
}
