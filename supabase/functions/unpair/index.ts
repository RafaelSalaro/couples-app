// docs/05 §3: `unpair`. The rules live in the SQL function `api_unpair`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("unpair", liveDeps()));
