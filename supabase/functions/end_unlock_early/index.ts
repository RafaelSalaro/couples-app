// docs/05 §3: `end_unlock_early`. The rules live in the SQL function `api_end_unlock_early`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("end_unlock_early", liveDeps()));
