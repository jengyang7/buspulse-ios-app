-- Phase 1 — Periodic estimate refresh + session expiry (BACKEND_DESIGN.md §5).
--
-- Without this, estimates only recompute on start_queue/board events, so the
-- censored floor goes stale between events (a person can keep waiting and the
-- number won't climb). This schedules a recompute every 30s and ages out
-- sessions left open too long.

create extension if not exists pg_cron;

-- Expire stale active sessions, then recompute every tile that has live
-- activity (open sessions, or boards within the lookback window).
create or replace function public.refresh_estimates()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  -- Age out sessions open longer than the 90-min lookback (§6 auto-expire).
  update public.queue_sessions
  set status = 'expired'
  where status = 'active'
    and started_at < now() - interval '90 minutes';

  for r in
    select distinct route_stop_id
    from public.queue_sessions
    where status = 'active'
       or (status = 'boarded' and boarded_at >= now() - interval '90 minutes')
  loop
    perform public.compute_estimate(r.route_stop_id);
  end loop;
end;
$$;

-- Run every 30 seconds (pg_cron ≥ 1.5 supports sub-minute interval syntax).
select cron.schedule('refresh-estimates', '30 seconds', $$select public.refresh_estimates();$$);
