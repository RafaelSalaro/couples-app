// docs/05 §3: `create_custom_challenge`. The rules live in the SQL function `api_create_custom_challenge`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("create_custom_challenge", liveDeps()));
