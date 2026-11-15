// docs/05 §3: `propose_schedule_change`. The rules live in the SQL function `api_propose_schedule_change`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("propose_schedule_change", liveDeps()));
