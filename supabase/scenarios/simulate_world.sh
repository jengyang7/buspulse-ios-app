#!/usr/bin/env bash
# Simulate a realistic spread of commuters across several tiles with varied
# timings — quiet stops, busy stops, and a surge — then show the result.
#
#   ./supabase/scenarios/simulate_world.sh
#
# Additive (does not reset). For a clean slate first: `supabase db reset`.
set -euo pipefail
API="http://127.0.0.1:54321"
KEY="sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
HERE="$(cd "$(dirname "$0")" && pwd)"
PSQL() { docker exec -i supabase_db_buspulse psql -U postgres -d postgres "$@"; }

echo "=== creating 14 simulated commuters ==="
STAMP=$(date +%s)
declare -a U
for i in $(seq 1 14); do
  U[$i]=$(curl -s -X POST "$API/auth/v1/signup" -H "apikey: $KEY" -H "Content-Type: application/json" \
    -d "{\"email\":\"sim${i}_${STAMP}@buspulse.app\",\"password\":\"supersecret123\"}" \
    | python3 -c "import sys,json;print(json.load(sys.stdin)['user']['id'])")
done
echo "  done."

echo "=== injecting sessions (varied routes, stops, timings) ==="
# Convenience: a route_stop id by (location, route).
rs() { echo "(select id from route_stops where location_id='$1' and route_id='$2')"; }

PSQL -v ON_ERROR_STOP=1 <<SQL
insert into queue_sessions (user_id, route_stop_id, status, started_at, boarded_at) values
  -- Woodlands · AC7  → QUIET: one short board, one just-joined
  ('${U[1]}',  $(rs woodlands_ckpt ac7), 'boarded', now()-interval '6 min',  now()-interval '2 min'),
  ('${U[2]}',  $(rs woodlands_ckpt ac7), 'active',  now()-interval '3 min',  null),

  -- Woodlands · CW   → BUSY: recent boards + people stuck waiting (floor bites)
  ('${U[3]}',  $(rs woodlands_ckpt cw),  'boarded', now()-interval '12 min', now()-interval '8 min'),
  ('${U[4]}',  $(rs woodlands_ckpt cw),  'boarded', now()-interval '15 min', now()-interval '4 min'),
  ('${U[5]}',  $(rs woodlands_ckpt cw),  'active',  now()-interval '13 min', null),
  ('${U[6]}',  $(rs woodlands_ckpt cw),  'active',  now()-interval '16 min', null),

  -- Woodlands · SBS  → MODERATE: one long completed wait, one mid-queue
  ('${U[7]}',  $(rs woodlands_ckpt sbs), 'boarded', now()-interval '23 min', now()-interval '6 min'),
  ('${U[8]}',  $(rs woodlands_ckpt sbs), 'active',  now()-interval '10 min', null),

  -- JB CIQ · CW      → SURGE: four people all stuck 19–26 min, nobody boarded
  ('${U[9]}',  $(rs jbciq cw),           'active',  now()-interval '21 min', null),
  ('${U[10]}', $(rs jbciq cw),           'active',  now()-interval '24 min', null),
  ('${U[11]}', $(rs jbciq cw),           'active',  now()-interval '19 min', null),
  ('${U[12]}', $(rs jbciq cw),           'active',  now()-interval '26 min', null),

  -- JB CIQ · AC7     → one quick board
  ('${U[13]}', $(rs jbciq ac7),          'boarded', now()-interval '9 min',  now()-interval '5 min'),
  ('${U[14]}', $(rs jbciq ac7),          'active',  now()-interval '7 min',  null);

-- recompute every affected tile now (cron would also do this within 30s)
select public.refresh_estimates();
SQL
echo "  injected 14 sessions across 5 tiles."
echo
"$HERE/queue_status.sh"
