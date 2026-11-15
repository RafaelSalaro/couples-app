#!/bin/bash
# End-to-end smoke test against the linked Supabase project (supabase link): the deployed
# Edge Functions and the REST API, called as the iPhone app calls them. Creates two
# throwaway users and deletes them. Keys come from the Supabase CLI and never touch disk.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.orbstack/bin:/opt/homebrew/bin:$PATH"
REF=$(cat supabase/.temp/project-ref)
KEYS=$(supabase projects api-keys --project-ref "$REF" -o json 2>/dev/null)
key() { python3 -c "
import sys,json
raw=sys.stdin.read(); keys=json.loads(raw[raw.find('['):raw.rfind(']')+1])
print(next(k['api_key'] for k in keys if k.get('name')==sys.argv[1]))" "$1" <<<"$KEYS"; }
export LIVE_SUPABASE_URL="https://$REF.supabase.co" LIVE_ANON_KEY="$(key anon)" LIVE_SERVICE_ROLE_KEY="$(key service_role)"
deno test --allow-env --allow-net supabase/functions/tests/live_smoke.ts "$@"
