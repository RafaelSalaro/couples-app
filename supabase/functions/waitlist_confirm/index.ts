// The link in the waitlist email: confirms, then sends the visitor to /waitlist/confirmed/.
import { adminClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const token = new URL(req.url).searchParams.get("token") ?? "";
  await adminClient().rpc("api_waitlist_confirm", { p_token: token });
  // Same page whatever happened: a used or unknown link is not an error worth showing.
  const domain = Deno.env.get("APP_DOMAIN") ?? "example.com";
  return new Response(null, { status: 303, headers: { location: `https://${domain}/waitlist/confirmed/`, "cache-control": "no-store" } });
});
