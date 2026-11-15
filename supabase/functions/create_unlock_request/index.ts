// docs/05 §3: `create_unlock_request`. The rules live in the SQL function `api_create_unlock_request`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("create_unlock_request", liveDeps()));
