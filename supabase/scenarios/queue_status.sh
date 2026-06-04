#!/usr/bin/env bash
# Backend status dashboard — run anytime to see live queue/passenger state.
#   ./supabase/scenarios/queue_status.sh
set -euo pipefail
PSQL() { docker exec supabase_db_buspulse psql -U postgres -d postgres "$@"; }

echo "════════════════════════════════════════════════════════════════"
echo " TILE STATUS  (computed estimates with any live activity)"
echo "════════════════════════════════════════════════════════════════"
PSQL -c "
select l.name as location, r.badge as route,
       e.low||'–'||e.high as range, e.estimate as est, e.crowd, e.confidence,
       e.active_count as waiting,
       round(e.n_eff::numeric,1) as eff_reports,
       round(extract(epoch from (now()-e.updated_at)))||'s' as updated_ago
from wait_estimates e
join route_stops rs on rs.id = e.route_stop_id
join routes r       on r.id  = rs.route_id
join locations l    on l.id  = rs.location_id
where e.active_count > 0 or e.n_eff > 0
order by l.name, e.estimate desc;"

echo "════════════════════════════════════════════════════════════════"
echo " PASSENGERS QUEUING RIGHT NOW  (active, censored observations)"
echo "════════════════════════════════════════════════════════════════"
PSQL -c "
select l.name as location, r.badge as route, u.email,
       round(extract(epoch from (now()-qs.started_at))/60,1) as waiting_min,
       to_char(qs.started_at,'HH24:MI:SS') as joined_at
from queue_sessions qs
join route_stops rs on rs.id = qs.route_stop_id
join routes r       on r.id  = rs.route_id
join locations l    on l.id  = rs.location_id
join auth.users u   on u.id  = qs.user_id
where qs.status = 'active'
order by waiting_min desc;"

echo "════════════════════════════════════════════════════════════════"
echo " RECENT BOARDINGS  (completed reports, last 30 min)"
echo "════════════════════════════════════════════════════════════════"
PSQL -c "
select l.name as location, r.badge as route, u.email,
       round(extract(epoch from (qs.boarded_at-qs.started_at))/60,1) as waited_min,
       round(extract(epoch from (now()-qs.boarded_at))/60,1) as boarded_min_ago
from queue_sessions qs
join route_stops rs on rs.id = qs.route_stop_id
join routes r       on r.id  = rs.route_id
join locations l    on l.id  = rs.location_id
join auth.users u   on u.id  = qs.user_id
where qs.status = 'boarded' and qs.boarded_at >= now() - interval '30 min'
order by qs.boarded_at desc;"
