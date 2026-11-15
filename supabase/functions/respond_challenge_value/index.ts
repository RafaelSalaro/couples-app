// docs/05 §3: `respond_challenge_value`. The rules live in the SQL function `api_respond_challenge_value`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("respond_challenge_value", liveDeps()));
