#!/usr/bin/env bash
# Show how many queue_session records each active route_stop has, so you can spot
# tiles that never get reports (0 boarded). Run anytime, e.g. while live_world.sh
# is feeding the DB:
#
#   ./supabase/scenarios/report_coverage.sh
#
set -uo pipefail
PSQL() { docker exec -i supabase_db_buspulse psql -U postgres -d postgres "$@"; }

PSQL <<'SQL'
select l.name as location, r.badge,
  count(*) filter (where q.status='active')    as active,
  count(*) filter (where q.status='boarded')   as boarded,
  count(*) filter (where q.status='abandoned') as abandoned,
  count(q.id)        as total,
  max(q.boarded_at)  as last_boarded
from route_stops rs
join locations l on l.id = rs.location_id
join routes r    on r.id = rs.route_id
left join queue_sessions q on q.route_stop_id = rs.id
where rs.active
group by l.name, r.badge
order by l.name, r.badge;

-- Tiles with no reports yet (these are the ones to worry about):
select l.name as location, r.badge, 'NO REPORTS' as status
from route_stops rs
join locations l on l.id = rs.location_id
join routes r    on r.id = rs.route_id
where rs.active
  and not exists (select 1 from queue_sessions q where q.route_stop_id = rs.id)
order by l.name, r.badge;
SQL
