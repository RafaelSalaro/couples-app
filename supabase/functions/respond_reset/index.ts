// docs/05 §3: `respond_reset`. The rules live in the SQL function `api_respond_reset`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("respond_reset", liveDeps()));
