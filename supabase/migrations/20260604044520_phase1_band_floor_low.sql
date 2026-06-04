-- Phase 1 fix — stop the [low, high] band from going absurdly wide.
--
-- Before: when a long active queue pushed `high` up (e.g. 36) but an old short
-- completed wait set `low` (e.g. 4), tiles showed "4–36 min". If everyone
-- currently queuing has waited 30+ min, the low end can't be 4.
--
-- Fix: lift `low` by the active queue's *lower* bound (P25 of active elapsed),
-- so the band reflects the range people are actually waiting right now.
-- Only this function changes; the interface (wait_estimates row) is unchanged.

create or replace function public.compute_estimate(p_route_stop_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m         numeric;   -- weighted median of completed waits
  v_low_raw   numeric;   -- weighted p25
  v_high_raw  numeric;   -- weighted p75
  v_neff      numeric;
  v_floor     numeric;   -- P75 of active elapsed (censored upper-ish bound)
  v_floor_lo  numeric;   -- P25 of active elapsed (censored lower bound) ← NEW
  v_active    integer;
  v_fresh     timestamptz;
  v_est       numeric;
  v_low       integer;
  v_high      integer;
  v_crowd     public.crowd_level;
  v_conf      text;
  v_fresh_min numeric;
  v_disp      numeric;
begin
  v_m        := public.completed_wpctl(p_route_stop_id, 0.5);
  v_low_raw  := public.completed_wpctl(p_route_stop_id, 0.25);
  v_high_raw := public.completed_wpctl(p_route_stop_id, 0.75);
  v_neff     := public.completed_neff(p_route_stop_id);

  -- Censored band from people currently queued: P25 (lower) and P75 (floor).
  select
    percentile_cont(0.75) within group (
      order by extract(epoch from (now() - started_at)) / 60.0),
    percentile_cont(0.25) within group (
      order by extract(epoch from (now() - started_at)) / 60.0),
    count(*)
  into v_floor, v_floor_lo, v_active
  from public.queue_sessions
  where route_stop_id = p_route_stop_id and status = 'active';

  select max(boarded_at) into v_fresh
  from public.queue_sessions
  where route_stop_id = p_route_stop_id and status = 'boarded'
    and boarded_at >= now() - interval '90 minutes';

  if coalesce(v_neff, 0) = 0 and coalesce(v_active, 0) = 0 then
    return;
  end if;

  v_est := greatest(coalesce(v_m, 0), coalesce(v_floor, 0));

  -- Low end: the completed p25, but never below what live queuers already prove
  -- (the active P25). This collapses the "4–36" case toward "30–36".
  v_low  := round(greatest(
              coalesce(v_low_raw, greatest(v_est - 3, 3)),
              coalesce(v_floor_lo, 0)));
  v_high := round(coalesce(v_high_raw, v_est));
  v_low  := greatest(least(v_low, round(v_est)), 3);          -- clamp(low, 3, est)
  v_high := greatest(v_high, round(v_est), v_low + 3);        -- max(high, est, low+MIN_BAND)

  v_crowd := case
               when v_est < 10 then 'low'
               when v_est < 20 then 'med'
               else 'high'
             end::public.crowd_level;

  v_fresh_min := case when v_fresh is null then 9999
                      else extract(epoch from (now() - v_fresh)) / 60.0 end;
  v_disp := (v_high - v_low) / greatest(v_est, 1);
  v_conf := case
              when v_neff >= 12 and v_fresh_min <= 5  and v_disp <= 0.5 then 'High'
              when v_neff >= 7  and v_fresh_min <= 15                    then 'Good'
              else 'Building'
            end;

  insert into public.wait_estimates as we
    (route_stop_id, low, high, estimate, crowd, confidence,
     n_eff, active_count, fresh_at, updated_at)
  values
    (p_route_stop_id, v_low, v_high, round(v_est), v_crowd, v_conf,
     coalesce(v_neff, 0), coalesce(v_active, 0), v_fresh, now())
  on conflict (route_stop_id) do update set
    low = excluded.low, high = excluded.high, estimate = excluded.estimate,
    crowd = excluded.crowd, confidence = excluded.confidence,
    n_eff = excluded.n_eff, active_count = excluded.active_count,
    fresh_at = excluded.fresh_at, updated_at = excluded.updated_at;
end;
$$;
