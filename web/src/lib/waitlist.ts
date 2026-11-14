// Client for the `waitlist_join` Edge Function (docs/05-data-model-and-api.md §3).
// Request:  POST JSON {email, source}
// Response: {ok: true, data} or {ok: false, error: {code, message}}
// Kept free of DOM access so it can be unit tested with a fake fetch.

export const messages = {
  sending: 'One moment…',
  success: 'Almost there. Check your inbox and confirm your email to join.',
  invalid_email: "That email doesn't look quite right. Mind checking it?",
  rate_limited: "That's a lot of tries in a short time. Please give it a minute and try again.",
  not_configured: "The waitlist isn't open just yet. Please check back soon.",
  network: "We couldn't reach the waitlist just now. Please try again in a moment.",
  unknown: 'Something went wrong on our side. Please try again in a moment.',
} as const;

export type WaitlistCode = 'invalid_email' | 'rate_limited' | 'not_configured' | 'network' | 'unknown';

export type WaitlistResult =
  | { ok: true; message: string }
  | { ok: false; code: WaitlistCode; message: string };

export interface WaitlistInput {
  endpoint: string;
  anonKey?: string;
  email: string;
  source: string;
  /** Value of the hidden honeypot field. Anything non-empty is treated as a bot. */
  honeypot?: string;
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
}

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export const isValidEmail = (value: string): boolean => value.length <= 254 && EMAIL.test(value);

const fail = (code: WaitlistCode): WaitlistResult => ({ ok: false, code, message: messages[code] });

export async function submitWaitlist(input: WaitlistInput): Promise<WaitlistResult> {
  const email = input.email.trim().toLowerCase();
  if (!isValidEmail(email)) return fail('invalid_email');
  // Bots that fill the hidden field get a friendly success and nothing is sent.
  if (input.honeypot && input.honeypot.trim() !== '') return { ok: true, message: messages.success };
  if (!input.endpoint) return fail('not_configured');

  const doFetch = input.fetchImpl ?? fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), input.timeoutMs ?? 10_000);
  try {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (input.anonKey) {
      headers.apikey = input.anonKey;
      headers.Authorization = `Bearer ${input.anonKey}`;
    }
    const response = await doFetch(input.endpoint, {
      method: 'POST',
      headers,
      body: JSON.stringify({ email, source: input.source }),
      signal: controller.signal,
    });
    let body: { ok?: boolean; error?: { code?: string } } | null = null;
    try {
      body = await response.json();
    } catch {
      body = null;
    }
    if (response.ok && body?.ok === true) return { ok: true, message: messages.success };
    const code = body?.error?.code;
    if (code === 'rate_limited' || response.status === 429) return fail('rate_limited');
    if (code === 'invalid_email' || code === 'invalid') return fail('invalid_email');
    return fail('unknown');
  } catch {
    return fail('network');
  } finally {
    clearTimeout(timer);
  }
}
