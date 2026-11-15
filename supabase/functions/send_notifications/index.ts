// Delivers the notifications outbox (APNs and Resend). Called every minute by pg_cron with
// the x-cron-secret header (docs/05 §4); never by the app.
import { sendApns, apnsPayload } from "../_shared/apns.ts";
import { authorized } from "../_shared/revenuecat.ts";
import { fail, json } from "../_shared/http.ts";
import { processOutbox, type OutboxItem } from "../_shared/outbox.ts";
import { sendEmail } from "../_shared/resend.ts";
import { adminClient, env } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (!authorized(req.headers.get("x-cron-secret"), Deno.env.get("CRON_SECRET") ?? "")) return fail("unauthorized", 401);
  const db = adminClient();
  const apns = {
    keyPem: env("APNS_KEY"), keyId: env("APNS_KEY_ID"), teamId: env("APNS_TEAM_ID"), topic: env("APNS_TOPIC"),
  };
  const counts = await processOutbox({
    claim: async (limit) => {
      const { data, error } = await db.rpc("claim_outbox", { p_limit: limit });
      if (error) throw error;
      return (data ?? []) as OutboxItem[];
    },
    finish: async (id, outcome) => {
      const { error } = await db.rpc("finish_outbox", { p_id: id, p_outcome: outcome });
      if (error) throw error;
    },
    issueUnlockEmailSecrets: async (requestId) => {
      const { data, error } = await db.rpc("issue_unlock_email_secrets", { p_request: requestId });
      if (error) throw error;
      return data;
    },
    removeToken: async (token) => { await db.from("push_tokens").delete().eq("token", token); },
    push: (token, environment, message, custom) => sendApns(apns, token, environment, apnsPayload(message, custom)),
    email: (to, message) => sendEmail(env("RESEND_API_KEY"), env("EMAIL_FROM"), to, message),
    appName: Deno.env.get("APP_NAME") ?? "Couples App",
    urlScheme: Deno.env.get("APP_URL_SCHEME") ?? "couplesapp",
    domain: Deno.env.get("APP_DOMAIN") ?? "example.com",
    functionsUrl: `${env("SUPABASE_URL")}/functions/v1`,
  });
  return json({ ok: true, data: counts });
});
