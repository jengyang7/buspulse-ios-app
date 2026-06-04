-- Phase 2 — Tighten the displayed band (UX: ranges like "9–22 min" aren't usable).
--
-- The central estimate (v_est) already blends the live median, the historical
-- prior, and the censored active-queue floor — it's the number to trust. The
-- band should only convey uncertainty *around* it, so we clamp each side to at
-- most ~±20% of the estimate (bounded to a 3–9 min half-width). This keeps a
-- tight data-driven band when real percentiles are tight, but reins in the
-- prior-dominated and single-slow-queuer cases that produced the wide ranges.
--
-- Only the band-clamp block (marked below) is new; everything else is carried
-- over verbatim from 20260604055456_phase2_history_and_prior.sql.

create or replace function public.compute_estimate(p_route_stop_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m         numeric;
  v_low_raw   numeric;
  v_high_raw  numeric;
  v_neff      numeric;
  v_floor     numeric;   -- P75 active elapsed (censored floor)
  v_floor_lo  numeric;   -- P25 active elapsed (band lower bound)
  v_active    integer;
  v_fresh     timestamptz;
  v_mu        numeric;   -- historical median (prior μ_h)
  v_sigma     numeric;   -- historical spread (prior σ_h)
  v_wd        text;
  v_hr        int;
  k           constant numeric := 3;   -- prior strength
  v_alpha     numeric;
  v_m_eff     numeric;
  v_shrunk    numeric;
  v_ratio     numeric;
  v_est       numeric;
  v_low       integer;
  v_high      integer;
  v_crowd     public.crowd_level;
  v_conf      text;
  v_fresh_min numeric;
  v_disp      numeric;
  v_cap       integer;   -- max half-width of the displayed band (new)
begin
  v_m        := public.completed_wpctl(p_route_stop_id, 0.5);
  v_low_raw  := public.completed_wpctl(p_route_stop_id, 0.25);
  v_high_raw := public.completed_wpctl(p_route_stop_id, 0.75);
  v_neff     := coalesce(public.completed_neff(p_route_stop_id), 0);

  select
    percentile_cont(0.75) within group (order by extract(epoch from (now() - started_at)) / 60.0),
    percentile_cont(0.25) within group (order by extract(epoch from (now() - started_at)) / 60.0),
    count(*)
  into v_floor, v_floor_lo, v_active
  from public.queue_sessions
  where route_stop_id = p_route_stop_id and status = 'active';

  select max(boarded_at) into v_fresh
  from public.queue_sessions
  where route_stop_id = p_route_stop_id and status = 'boarded'
    and boarded_at >= now() - interval '90 minutes';

  -- Prior for the current weekday-type × hour bucket.
  v_wd := case when extract(isodow from now()) >= 6 then 'weekend' else 'weekday' end;
  v_hr := extract(hour from now())::int;
  select median, coalesce(std, (p75 - p25) / 1.349)
  into v_mu, v_sigma
  from public.wait_history
  where route_stop_id = p_route_stop_id and weekday_type = v_wd and hour = v_hr;

  -- No live data AND no prior → nothing to say.
  if v_neff = 0 and coalesce(v_active, 0) = 0 and v_mu is null then
    return;
  end if;

  -- Central estimate: shrink the live median toward the prior, then never below
  -- what live queuers already prove (the censored floor).
  if v_mu is not null then
    v_m_eff  := coalesce(v_m, v_mu);
    v_shrunk := (v_neff * v_m_eff + k * v_mu) / (v_neff + k);
  else
    v_shrunk := coalesce(v_m, 0);
  end if;
  v_est := greatest(v_shrunk, coalesce(v_floor, 0));

  -- Band: blend live percentiles with the prior band, weighted by data volume.
  v_alpha := v_neff / (v_neff + k);
  if v_mu is not null then
    v_low  := round(v_alpha * coalesce(v_low_raw, v_mu)  + (1 - v_alpha) * greatest(v_mu - coalesce(v_sigma, 0), 1));
    v_high := round(v_alpha * coalesce(v_high_raw, v_mu) + (1 - v_alpha) * (v_mu + coalesce(v_sigma, 0)));
  else
    v_low  := round(coalesce(v_low_raw, greatest(v_est - 3, 3)));
    v_high := round(coalesce(v_high_raw, v_est));
  end if;
  v_low  := greatest(v_low, round(coalesce(v_floor_lo, 0)));   -- lift by active floor
  v_low  := greatest(least(v_low, round(v_est)), 3);            -- clamp(low, 3, est)
  v_high := greatest(v_high, round(v_est), v_low + 3);          -- max(high, est, low+MIN_BAND)

  -- NEW — tighten the band around the estimate so it stays commuter-readable.
  -- Half-width capped at ~20% of the estimate, bounded to [3, 9] minutes. A
  -- genuinely tight real band stays tight; wide prior/slow-queuer bands shrink.
  v_cap  := least(greatest(round(0.20 * v_est), 3), 9);
  v_low  := greatest(v_low,  round(v_est) - v_cap);
  v_high := least(v_high, round(v_est) + v_cap);
  v_low  := greatest(least(v_low, round(v_est)), 3);   -- re-clamp(low, 3, est)
  v_high := greatest(v_high, round(v_est), v_low + 3); -- keep min band + cover est

  -- Crowd relative to THIS route's own normal (§2.6), else absolute fallback.
  if v_mu is not null and v_mu > 0 then
    v_ratio := v_est / v_mu;
    v_crowd := case when v_ratio < 0.85 then 'low'
                    when v_ratio < 1.25 then 'med'
                    else 'high' end::public.crowd_level;
  else
    v_crowd := case when v_est < 10 then 'low'
                    when v_est < 20 then 'med'
                    else 'high' end::public.crowd_level;
  end if;

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
     v_neff, coalesce(v_active, 0), v_fresh, now())
  on conflict (route_stop_id) do update set
    low = excluded.low, high = excluded.high, estimate = excluded.estimate,
    crowd = excluded.crowd, confidence = excluded.confidence,
    n_eff = excluded.n_eff, active_count = excluded.active_count,
    fresh_at = excluded.fresh_at, updated_at = excluded.updated_at;
end;
$$;
