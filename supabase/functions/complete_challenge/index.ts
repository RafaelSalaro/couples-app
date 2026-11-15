// docs/05 §3: `complete_challenge`. The rules live in the SQL function `api_complete_challenge`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("complete_challenge", liveDeps()));
