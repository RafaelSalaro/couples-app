// Email through Resend. Secrets: RESEND_API_KEY, EMAIL_FROM ("Name <hello@domain>").
import type { EmailMessage } from "./messages.ts";

export async function sendEmail(
  apiKey: string, from: string, to: string, message: EmailMessage, fetcher: typeof fetch = fetch,
): Promise<{ ok: boolean; status: number }> {
  const res = await fetcher("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
    body: JSON.stringify({ from, to: [to], subject: message.subject, text: message.text, html: message.html }),
  });
  await res.body?.cancel();
  return { ok: res.ok, status: res.status };
}
