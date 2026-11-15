#!/bin/bash
# Concurrent spends never over-spend (docs/07 §3 "Minutes"): two sessions each try to spend
# 30 of a 30-minute balance at the same moment; exactly one may succeed.
# pgTAP runs in one session, so this needs two real connections. Uses the local Supabase
# database container (run `supabase start` first). Leaves no data behind.
set -euo pipefail
export PATH="$HOME/.orbstack/bin:$PATH"
DB="${SUPABASE_DB_CONTAINER:-supabase_db_couples-app}"
psql() { docker exec -i "$DB" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -qtA "$@"; }

USER_ID=$(psql <<'SQL'
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'concurrency-' || gen_random_uuid() || '@example.com', now(), now())
returning id;
SQL
)
USER_ID=$(echo "$USER_ID" | head -1)
TMP=$(mktemp -d)
cleanup() {
  psql -c "delete from public.profiles where id = '$USER_ID'; delete from auth.users where id = '$USER_ID'" >/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

psql -c "select public.grant_minutes('$USER_ID', null, 30, 'earn_challenge')" >/dev/null

# Both sessions start, take a moment inside their transaction, then spend 30.
spend() {
  psql 2>&1 <<SQL || true
begin;
select pg_sleep(0.3);
select public.spend_minutes('$USER_ID', null, 30);
commit;
select 'spent';
SQL
}
spend > "$TMP/a" & A=$!
spend > "$TMP/b" & B=$!
wait $A $B
OUT="$(cat "$TMP/a" "$TMP/b")"

SPENT=$(grep -c '^spent$' <<<"$OUT" || true)
REFUSED=$(grep -c '^ERROR:  insufficient' <<<"$OUT" || true)
BALANCE=$(psql -c "select public.balance_of('$USER_ID')" | head -1)
LEDGER=$(psql -c "select coalesce(-sum(minutes), 0) from public.minute_ledger where user_id = '$USER_ID' and type = 'spend_unlock'" | head -1)

echo "spent: $SPENT, refused: $REFUSED, balance: $BALANCE, ledger spends: $LEDGER"
if [ "$SPENT" = 1 ] && [ "$REFUSED" = 1 ] && [ "$BALANCE" = 0 ] && [ "$LEDGER" = 30 ]; then
  echo "PASS: concurrent spends never over-spend"
else
  echo "FAIL"; echo "$OUT"; exit 1
fi
