// docs/05 §3: `give_kudos`. The rules live in the SQL function `api_give_kudos`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("give_kudos", liveDeps()));
