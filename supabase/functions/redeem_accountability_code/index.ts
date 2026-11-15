// docs/05 §3: `redeem_accountability_code`. The rules live in the SQL function `api_redeem_accountability_code`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("redeem_accountability_code", liveDeps()));
