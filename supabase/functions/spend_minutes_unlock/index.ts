// docs/05 §3: `spend_minutes_unlock`. The rules live in the SQL function `api_spend_minutes_unlock`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("spend_minutes_unlock", liveDeps()));
