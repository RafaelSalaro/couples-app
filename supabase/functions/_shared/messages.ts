// What each queued notification says (docs/03 §11, brand voice in docs/10). English only at
// launch. Pure functions: the sender fills in names and links, tests check the copy.

export interface PushMessage {
  title: string;
  body: string;
  /** APNs category for actionable notifications (docs/06 §9). */
  category?: "UNLOCK_REQUEST" | "COMPLETION_CONFIRM" | "SCHEDULE_CHANGE";
  /** Time-sensitive breaks through Focus: unlock requests only. */
  timeSensitive?: boolean;
  /** Deep link the app opens (couplesapp://…). */
  link?: string;
  /** Silent: tells the app to refresh without showing anything. */
  silent?: boolean;
}

export interface EmailMessage {
  subject: string;
  text: string;
  html: string;
}

type Payload = Record<string, unknown>;
const n = (value: unknown) => Number(value ?? 0);
const min = (value: unknown) => `${n(value)} min`;

/** The push for an outbox row, or null when the kind has no push (it is email-only). */
export function pushFor(kind: string, payload: Payload, partner: string, scheme: string): PushMessage | null {
  const reason = typeof payload.reason === "string" && payload.reason ? ` · “${payload.reason}”` : "";
  switch (kind) {
    case "unlock_request":
      return {
        title: `${partner} asks for ${min(payload.minutes)}`, body: `${partner} asks for ${min(payload.minutes)}${reason}`,
        category: "UNLOCK_REQUEST", timeSensitive: true, link: `${scheme}://request/${payload.request_id}`,
      };
    case "unlock_approved": return { title: "Go for it", body: `${partner} said go for it. Enjoy your ${min(payload.minutes)}.`, link: `${scheme}://unlock` };
    case "unlock_declined": return { title: "Maybe later", body: `${partner} says let's wait — maybe later?` };
    case "unlock_expired": return { title: "No answer this time", body: "You can try again or use your minutes." };
    case "challenge_done":
      return {
        title: `${partner} did “${payload.title}”`, body: "Confirm with one tap and the minutes arrive.",
        category: "COMPLETION_CONFIRM", link: `${scheme}://challenge/${payload.challenge_id}`,
      };
    case "challenge_confirmed": return { title: "Confirmed", body: `${partner} confirmed it · +${min(payload.minutes)}`, link: `${scheme}://minutes` };
    case "challenge_value_proposed":
      return { title: "A new challenge", body: `${partner} added “${payload.title}” for ${min(payload.minutes)} — sounds right?`, link: `${scheme}://challenge/${payload.challenge_id}` };
    case "challenge_value_countered": return { title: "A different value", body: `${partner} suggests ${min(payload.minutes)}. Sounds right?`, link: `${scheme}://challenge/${payload.challenge_id}` };
    case "challenge_value_approved": return { title: "Agreed", body: `${partner} agreed: ${min(payload.minutes)}.`, link: `${scheme}://challenge/${payload.challenge_id}` };
    case "kudos_received": {
      const message = typeof payload.message === "string" && payload.message ? ` · “${payload.message}”` : "";
      return { title: `Kudos from ${partner}`, body: `${partner} sent kudos${message} · +${min(payload.minutes)}`, link: `${scheme}://minutes` };
    }
    case "schedule_change_requested":
      return { title: "Protected time", body: `${partner} would like to change protected time.`, category: "SCHEDULE_CHANGE", link: `${scheme}://schedule` };
    case "schedule_change_approved": return { title: "Protected time", body: `${partner} approved your change.`, link: `${scheme}://schedule` };
    case "schedule_change_declined": return { title: "Protected time", body: `${partner} would like to talk about it first.`, link: `${scheme}://schedule` };
    case "reset_proposed": return { title: "A fresh start?", body: `${partner} suggests resetting both balances to ${min(payload.standard_minutes)}.`, link: `${scheme}://minutes` };
    case "reset_accepted": return { title: "A fresh start", body: `${partner} agreed. You both have ${min(payload.standard_minutes)}.`, link: `${scheme}://minutes` };
    case "reset_declined": return { title: "Balances stay", body: `${partner} would rather keep your balances as they are.`, link: `${scheme}://minutes` };
    case "minutes_expiring": return { title: "Minutes expiring", body: `${n(payload.minutes)} of your minutes expire tomorrow — maybe a walk together?`, link: `${scheme}://minutes` };
    case "weekly_report": return { title: "Your week together", body: "Your weekly report is ready.", link: `${scheme}://report` };
    case "emergency_used": return { title: partner, body: `${partner} used an emergency unlock.` };
    case "unpaired": return { title: partner, body: `${partner} ended your pairing.` };
    case "protected_time_off": return { title: partner, body: `Protected time is off on ${partner}'s phone.` };
    case "protected_time_on": return { title: partner, body: `Protected time is back on on ${partner}'s phone.` };
    case "paired": return { title: "You're paired", body: `You're now paired with ${partner}.` };
    case "qr_secret_rotated": return { title: "", body: "", silent: true };
    default: return null;
  }
}

function escape(text: string): string {
  return text.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

function layout(app: string, paragraphs: string[], action?: { label: string; url: string }): string {
  const body = paragraphs.map((p) => `<p style="margin:0 0 16px">${escape(p)}</p>`).join("");
  const button = action
    ? `<p style="margin:24px 0"><a href="${escape(action.url)}" style="background:#C2593F;color:#FFF8F0;padding:12px 20px;border-radius:14px;text-decoration:none;font-weight:600">${escape(action.label)}</a></p>`
    : "";
  return `<!doctype html><html><body style="margin:0;background:#FBF6EF;color:#2B2422;font:16px/1.5 -apple-system,Helvetica,Arial,sans-serif"><div style="max-width:520px;margin:0 auto;padding:32px 24px">${body}${button}<p style="margin:32px 0 0;color:#6E625C;font-size:13px">${escape(app)}</p></div></body></html>`;
}

/** The ask-your-partner fallback email with the approve link and the 6-digit code (§6.2). */
export function unlockRequestEmail(app: string, partner: string, minutes: number, reason: string | null, code: string, approveUrl: string): EmailMessage {
  const ask = `${partner} asks for ${minutes} minutes${reason ? ` · “${reason}”` : ""}.`;
  const lines = [
    ask,
    "If it feels right, approve it here. Or share this code with them in person or by message:",
    code.split("").join(" "),
    "It works once and expires with the request in a few minutes.",
  ];
  return {
    subject: `${partner} asks for ${minutes} minutes`,
    text: `${ask}\n\nApprove: ${approveUrl}\n\nOr share this code: ${code}\n\nIt works once and expires with the request in a few minutes.\n\n${app}`,
    html: layout(app, lines, { label: "Go for it", url: approveUrl }),
  };
}

/** Double opt-in for the website's waitlist. */
export function waitlistEmail(app: string, confirmUrl: string): EmailMessage {
  const lines = [`Thanks for your interest in ${app}.`, "Please confirm your email so we can tell you when it is ready. If this wasn't you, ignore this message."];
  return {
    subject: `Confirm your email for ${app}`,
    text: `${lines.join("\n\n")}\n\nConfirm: ${confirmUrl}\n\n${app}`,
    html: layout(app, lines, { label: "Confirm my email", url: confirmUrl }),
  };
}

/** The optional weekly report email (off by default, P24). */
export function weeklyReportEmail(app: string, partner: string, summary: { earned: number; together: number; streak: number }, url: string): EmailMessage {
  const lines = [
    `Your week with ${partner}: ${summary.together} minutes earned together.`,
    `You earned ${summary.earned} minutes. Your shared streak is ${summary.streak} days.`,
  ];
  return { subject: `Your week with ${partner}`, text: `${lines.join("\n\n")}\n\n${url}\n\n${app}`, html: layout(app, lines, { label: "See the week", url }) };
}
