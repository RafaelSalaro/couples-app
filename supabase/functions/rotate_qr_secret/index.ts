// docs/05 §3: `rotate_qr_secret`. The rules live in the SQL function `api_rotate_qr_secret`.
import { apiHandler } from "../_shared/api.ts";
import { liveDeps } from "../_shared/supabase.ts";

Deno.serve(apiHandler("rotate_qr_secret", liveDeps()));
