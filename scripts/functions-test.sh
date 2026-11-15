#!/bin/bash
# Deno tests of the Edge Functions: unit tests always; the integration tests too when the
# local Supabase stack is running (`supabase start`).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.orbstack/bin:$PATH"
if STATUS=$(supabase status -o env 2>/dev/null); then
  eval "$(grep -E '^(API_URL|SERVICE_ROLE_KEY|ANON_KEY)=' <<<"$STATUS")"
  export SUPABASE_URL="$API_URL" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" SUPABASE_ANON_KEY="$ANON_KEY"
else
  echo "Local stack not running: integration tests are skipped."
fi
deno test --allow-env --allow-net supabase/functions/tests/ "$@"
