// The website's waitlist form (web/README.md): {email, source} → double opt-in email.
// Public (no sign-in). Joining twice answers the same, so the form never reveals who is on the list.
import { ApiError, fromDatabaseError, readBody, respond } from "../_shared/http.ts";
import { adminClient } from "../_shared/supabase.ts";

async function clientKey(req: Request): Promise<string> {
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? req.headers.get("cf-connecting-ip") ?? "unknown";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`waitlist:${ip}`));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve((req) =>
  respond(req, async () => {
    const body = await readBody(req);
    // Honeypot field the form hides from people: bots fill it, and get a quiet success.
    if (typeof body.website === "string" && body.website) return { joined: true };
    if (typeof body.email !== "string") throw new ApiError("invalid_email");
    const { data, error } = await adminClient().rpc("api_waitlist_join", {
      p_email: body.email, p_source: typeof body.source === "string" ? body.source : null, p_client_key: await clientKey(req),
    });
    if (error) throw fromDatabaseError(error);
    return data;
  })
);
