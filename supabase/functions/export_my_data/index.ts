// docs/05 §3: `export_my_data`. The rules live in the SQL function `api_export_my_data`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("export_my_data", liveDeps()));
