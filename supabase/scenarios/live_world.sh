#!/usr/bin/env bash
# Continuous "real-world" feed: a pool of commuters keeps joining queues,
# waiting, and boarding, so the app shows live, ever-changing estimates.
#
#   ./supabase/scenarios/live_world.sh            # run until Ctrl-C
#   ./supabase/scenarios/live_world.sh 20         # run for ~20 minutes
#
# Leave it running in a terminal and watch the app update on its own.
set -uo pipefail
API="http://127.0.0.1:54321"
KEY="sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
PSQL() { docker exec -i supabase_db_buspulse psql -U postgres -d postgres -At "$@"; }
DURATION_MIN="${1:-0}"               # 0 = forever
TICK=12                              # seconds between events

# Tiles the simulated world covers (location route — weighted by repetition).
TILES=(
  "woodlands_ckpt ac7" "woodlands_ckpt cw" "woodlands_ckpt cw" "woodlands_ckpt sbs"
  "jbciq cw" "jbciq cw" "jbciq sbs" "jbciq 950"
  "kranji cw" "kranji sbs" "larkin sbs" "larkin cw"
)
rs_id() { PSQL -c "select id from route_stops where location_id='$1' and route_id='$2';"; }

echo "=== seeding a pool of 20 commuters ==="
STAMP=$(date +%s)
for i in $(seq 1 20); do
  curl -s -X POST "$API/auth/v1/signup" -H "apikey: $KEY" -H "Content-Type: application/json" \
    -d "{\"email\":\"sim${i}_${STAMP}@buspulse.app\",\"password\":\"supersecret123\"}" >/dev/null || true
done
echo "  pool ready. starting live feed (tick=${TICK}s, duration=${DURATION_MIN}m, Ctrl-C to stop)."
echo

END=0; [ "$DURATION_MIN" -gt 0 ] && END=$(( $(date +%s) + DURATION_MIN*60 ))
while true; do
  [ "$END" -gt 0 ] && [ "$(date +%s)" -ge "$END" ] && { echo "done."; break; }
  r=$(( RANDOM % 100 ))

  if [ "$r" -lt 55 ]; then
    # NEW JOINER: an idle commuter joins a (weighted) random tile.
    sel="${TILES[$((RANDOM % ${#TILES[@]}))]}"; read -r loc route <<<"$sel"
    rs=$(rs_id "$loc" "$route")
    uid=$(PSQL -c "select u.id from auth.users u
           where u.email like 'sim%' and not exists (
             select 1 from queue_sessions q where q.user_id=u.id and q.status='active')
           order by random() limit 1;")
    if [ -n "$uid" ] && [ -n "$rs" ]; then
      PSQL -c "insert into queue_sessions(user_id,route_stop_id,status,started_at)
               values('$uid','$rs','active', now());" >/dev/null
      action="join   $loc/$route"
    fi
  elif [ "$r" -lt 88 ]; then
    # BOARD: the longest-waiting person who's queued > 3 min boards.
    sid=$(PSQL -c "select id from queue_sessions where status='active'
                   and started_at < now()-interval '3 min' order by started_at limit 1;")
    if [ -n "$sid" ]; then
      PSQL -c "update queue_sessions set status='boarded', boarded_at=now() where id='$sid';" >/dev/null
      action="board  (longest waiter)"
    else
      action="(nobody ready to board)"
    fi
  else
    # ABANDON: someone gives up after a long wait (right-censored, dropped).
    sid=$(PSQL -c "select id from queue_sessions where status='active'
                   and started_at < now()-interval '20 min' order by random() limit 1;")
    if [ -n "$sid" ]; then
      PSQL -c "update queue_sessions set status='abandoned' where id='$sid';" >/dev/null
      action="abandon(>20m wait)"
    else
      action="(quiet tick)"
    fi
  fi

  PSQL -c "select public.refresh_estimates();" >/dev/null
  active=$(PSQL -c "select count(*) from queue_sessions where status='active';")
  echo "$(date +%H:%M:%S)  ${action:-tick}   ·   active queuers now: ${active}"
  sleep "$TICK"
done
