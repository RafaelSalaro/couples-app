// docs/05 §3: `sync_qr_unlocks`. The rules live in the SQL function `api_sync_qr_unlocks`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("sync_qr_unlocks", liveDeps()));
