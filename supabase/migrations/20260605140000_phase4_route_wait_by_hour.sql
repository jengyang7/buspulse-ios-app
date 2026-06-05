-- Phase 4 — Per-route, per-hour wait curve for a location on a given day.
--
-- Supersedes location_wait_by_hour: the Stats "Today vs last week" chart now
-- draws one line per route (multi-select), so it needs the route_stop dimension.
-- Same SECURITY DEFINER, network-wide-rollup rationale as live_activity(); hour
-- is bucketed in Singapore local time from started_at.

drop function if exists public.location_wait_by_hour(text, date);

create or replace function public.route_wait_by_hour(p_location_id text, p_date date)
returns table(route_stop_id uuid, hour smallint, wait integer, sample_count integer)
language sql
security definer
set search_path = ''
as $$
  select
    s.route_stop_id,
    extract(hour from s.started_at at time zone 'Asia/Singapore')::smallint as hour,
    round(percentile_cont(0.5) within group (
      order by extract(epoch from (s.boarded_at - s.started_at)) / 60.0))::int as wait,
    count(*)::int as sample_count
  from public.queue_sessions s
  join public.route_stops rs on rs.id = s.route_stop_id
  where rs.location_id = p_location_id
    and s.status = 'boarded'
    and s.boarded_at is not null
    and (s.started_at at time zone 'Asia/Singapore')::date = p_date
  group by s.route_stop_id, 2;
$$;

grant execute on function public.route_wait_by_hour(text, date) to anon, authenticated;
