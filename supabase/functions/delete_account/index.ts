// docs/05 §3: `delete_account`. The rules live in the SQL function `api_delete_account`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("delete_account", liveDeps()));
