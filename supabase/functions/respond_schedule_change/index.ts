// docs/05 §3: `respond_schedule_change`. The rules live in the SQL function `api_respond_schedule_change`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("respond_schedule_change", liveDeps()));
