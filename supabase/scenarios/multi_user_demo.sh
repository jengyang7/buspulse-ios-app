#!/usr/bin/env bash
# Multi-user queuing demo against the LOCAL Supabase stack.
#
# Simulates several riders on one tile (Larkin · SBS): some have already boarded
# (completed reports, at varying freshness) and some are still queuing (censored
# observations). Then it recomputes the estimate and shows how it moves.
#
# Usage:  supabase start  &&  ./supabase/scenarios/multi_user_demo.sh
set -euo pipefail

API="http://127.0.0.1:54321"
KEY="sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
PSQL() { docker exec -i supabase_db_buspulse psql -U postgres -d postgres "$@"; }
RPC() { # RPC <jwt> <fn> <json>
  curl -s -X POST "$API/rest/v1/rpc/$2" \
    -H "apikey: $KEY" -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" -d "$3"
}

# route_stop UUIDs are regenerated on every `db reset`, so resolve by natural key.
RS=$(PSQL -At -c "select id from route_stops where location_id='larkin' and route_id='sbs';")
STAMP=$(date +%s)
echo "Target tile (Larkin · SBS) route_stop = $RS"

echo "=== 1. Create 5 test users (signup → auth.users + profile trigger) ==="
declare -a UID_ARR TOKEN_ARR
for i in 1 2 3 4 5; do
  resp=$(curl -s -X POST "$API/auth/v1/signup" -H "apikey: $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"rider${i}_${STAMP}@buspulse.app\",\"password\":\"supersecret123\",\"data\":{\"display_name\":\"Rider $i\"}}")
  UID_ARR[$i]=$(echo "$resp"   | python3 -c "import sys,json;print(json.load(sys.stdin)['user']['id'])")
  TOKEN_ARR[$i]=$(echo "$resp" | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
  echo "  rider $i -> ${UID_ARR[$i]}"
done

echo
echo "=== 2. BEFORE: current estimate for Larkin · SBS ==="
PSQL -c "select low,high,estimate,crowd,confidence,round(n_eff::numeric,1) n_eff,active_count
         from wait_estimates where route_stop_id='$RS';"

echo "=== 3. Inject reports directly (controlled timestamps) ==="
# Three COMPLETED boards — note the freshest one (9 min wait, boarded 4 min ago)
# should dominate the recency-weighted median over the stale 20-min one.
#   rider1: waited 20 min, but boarded 50 min ago  -> heavily down-weighted (stale)
#   rider2: waited  8 min,        boarded 22 min ago
#   rider3: waited  9 min,        boarded  4 min ago  -> freshest, dominant
# Two STILL QUEUING (censored) — each elapsed ~26-29 min, nobody boarded yet:
#   rider4: started 29 min ago, active
#   rider5: started 26 min ago, active
PSQL -v ON_ERROR_STOP=1 <<SQL
insert into queue_sessions (user_id, route_stop_id, status, started_at, boarded_at) values
  ('${UID_ARR[1]}','$RS','boarded', now()-interval '70 min', now()-interval '50 min'),
  ('${UID_ARR[2]}','$RS','boarded', now()-interval '30 min', now()-interval '22 min'),
  ('${UID_ARR[3]}','$RS','boarded', now()-interval '13 min', now()-interval '4 min'),
  ('${UID_ARR[4]}','$RS','active',  now()-interval '29 min', null),
  ('${UID_ARR[5]}','$RS','active',  now()-interval '26 min', null);
select public.compute_estimate('$RS');
SQL

echo
echo "=== 4. AFTER: estimate recomputed ==="
echo "    Completed waits are ~8-9 min (fresh) + one stale 20 min;"
echo "    but 2 people have been queuing ~26-29 min with no board ->"
echo "    the CENSORED FLOOR pushes the estimate up to ~the active P75."
PSQL -c "select low,high,estimate,crowd,confidence,round(n_eff::numeric,1) n_eff,active_count
         from wait_estimates where route_stop_id='$RS';"

echo "=== 5. One queuing rider boards via the REAL RPC (auth + points) ==="
# rider4's active session id, then call board() as rider4 over PostgREST.
SID=$(PSQL -At -c "select id from queue_sessions where user_id='${UID_ARR[4]}' and route_stop_id='$RS' and status='active';")
echo "  rider4 active session: $SID"
RPC "${TOKEN_ARR[4]}" "board" "{\"p_session_id\":\"$SID\"}" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('  board() ->',d if isinstance(d,dict) and 'message' in d else 'status='+d.get('status','?')+' boarded_at='+str(d.get('boarded_at')))"
echo "  rider4 points:"
PSQL -c "select p.display_name, p.reward_points, l.delta, l.reason
         from profiles p join reward_ledger l on l.user_id=p.id where p.id='${UID_ARR[4]}';"

echo
echo "=== 6. AFTER board: floor recomputed (one fewer censored queuer) ==="
PSQL -c "select low,high,estimate,crowd,confidence,round(n_eff::numeric,1) n_eff,active_count
         from wait_estimates where route_stop_id='$RS';"

echo
echo "Done. Re-run after 'supabase db reset' for a clean slate."
