// docs/05 §3: `propose_reset`. The rules live in the SQL function `api_propose_reset`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("propose_reset", liveDeps()));
