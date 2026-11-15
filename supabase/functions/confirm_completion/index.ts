// docs/05 §3: `confirm_completion`. The rules live in the SQL function `api_confirm_completion`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("confirm_completion", liveDeps()));
