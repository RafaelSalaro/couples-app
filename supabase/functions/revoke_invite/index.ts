// docs/05 §3: `revoke_invite`. The rules live in the SQL function `api_revoke_invite`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("revoke_invite", liveDeps()));
