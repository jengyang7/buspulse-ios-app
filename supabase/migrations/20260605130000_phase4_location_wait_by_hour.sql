-- Phase 4 — Per-hour wait curve for a location on a given day.
--
-- Powers the Stats "Today vs same day last week" line chart. Returns the median
-- boarded wait (minutes) for each hour of the requested calendar day at one
-- location, bucketed in Singapore local time so the x-axis reads in SG hours.
--
-- queue_sessions is RLS-locked to each owner, but this is a network-wide rollup
-- (no PII, only hour + median + count), so it runs SECURITY DEFINER like
-- live_activity(). The hour is taken from started_at — the moment the rider
-- joined the queue is the hour they actually experienced that wait.

create or replace function public.location_wait_by_hour(p_location_id text, p_date date)
returns table(hour smallint, wait integer, sample_count integer)
language sql
security definer
set search_path = ''
as $$
  select
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
  group by 1;
$$;

grant execute on function public.location_wait_by_hour(text, date) to anon, authenticated;
