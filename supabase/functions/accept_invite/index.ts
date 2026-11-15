// docs/05 §3: `accept_invite`. The rules live in the SQL function `api_accept_invite`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("accept_invite", liveDeps()));
