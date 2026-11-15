// The web approve page (/approve/<token>, decision E8): {token, approve}. Public: the token
// in the partner's email is the proof. Same outcome as "Go for it" / "Let's wait" in the app.
import { fromDatabaseError, readBody, respond } from "../_shared/http.ts";
import * as v from "../_shared/input.ts";
import { ApiError } from "../_shared/http.ts";
import { adminClient } from "../_shared/supabase.ts";

Deno.serve((req) =>
  respond(req, async () => {
    const body = await readBody(req);
    const { data, error } = await adminClient().rpc("api_respond_unlock_by_token", {
      p_token: v.text(body, "token", 128), p_approve: v.bool(body, "approve"),
    });
    if (error) throw fromDatabaseError(error);
    const outcome = data as { error?: string; request?: { status?: string } } | null;
    if (outcome?.error) throw new ApiError(outcome.error);
    return { status: outcome?.request?.status ?? null };
  })
);
