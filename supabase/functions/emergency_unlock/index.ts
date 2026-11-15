// docs/05 §3: `emergency_unlock`. The rules live in the SQL function `api_emergency_unlock`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("emergency_unlock", liveDeps()));
