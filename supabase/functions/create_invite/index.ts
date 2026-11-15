// docs/05 §3: `create_invite`. The rules live in the SQL function `api_create_invite`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("create_invite", liveDeps()));
