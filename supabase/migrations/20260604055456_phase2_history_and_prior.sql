-- Phase 2 — Historical model + Bayesian prior (BACKEND_DESIGN.md §3, §2.4–2.6).
--
-- Adds:
--   1. wait_history baseline seeding (so cold start has a sane "typical wait").
--   2. an EWMA trigger that updates history on every board (any path).
--   3. compute_estimate rewired to shrink toward the prior, widen the band when
--      data is thin, derive crowd from the route's OWN baseline, and produce a
--      prior-only estimate when there's no live data at all.
--   4. refresh_estimates recomputes every tile (cheap here) so quiet tiles track
--      the hourly prior, not a frozen value.

-- 1. Baseline prior ------------------------------------------------------------
-- Fills wait_history for every tile × {weekday,weekend} × hour from the current
-- wait_estimates midpoint, shaped by a peak/off-peak/weekend factor (mirrors the
-- prototype's genWait). Real boards then refine it via the EWMA trigger.
create or replace function public.seed_wait_history_baseline()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.wait_history;
  insert into public.wait_history
    (route_stop_id, weekday_type, hour, median, p25, p75, mean, std, sample_count, updated_at)
  select rs.id, x.wtype, x.hour,
         x.med * x.fac,            -- median
         x.med * x.fac * 0.78,     -- p25  (~ median − 0.674σ, σ≈0.28·median)
         x.med * x.fac * 1.22,     -- p75
         x.med * x.fac,            -- mean
         x.med * x.fac * 0.28,     -- std
         25, now()                 -- pretend a decent prior strength
  from public.route_stops rs
  join public.wait_estimates e on e.route_stop_id = rs.id
  cross join (values ('weekday'), ('weekend')) as wt(wtype)
  cross join generate_series(0, 23) as h(hour)
  cross join lateral (
    select e.estimate::numeric as med, wt.wtype, h.hour,
           case
             when h.hour between 7 and 9 or h.hour between 17 and 20 then 1.45  -- peak
             when wt.wtype = 'weekend'                                then 0.80  -- weekend
             when h.hour < 6 or h.hour >= 23                          then 0.60  -- night
             else 0.90
           end as fac
  ) x;
end;
$$;

-- 2. EWMA history update on board (path-agnostic trigger) ----------------------
create or replace function public.on_board_update_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wait numeric;
  v_wd   text;
  v_hr   int;
  a      constant numeric := 0.1;   -- EWMA weight on the newest sample
begin
  if new.status = 'boarded' and old.status = 'active' and new.boarded_at is not null then
    v_wait := extract(epoch from (new.boarded_at - new.started_at)) / 60.0;
    if v_wait >= 0.5 and v_wait <= 90 then
      v_wd := case when extract(isodow from new.boarded_at) >= 6 then 'weekend' else 'weekday' end;
      v_hr := extract(hour from new.boarded_at)::int;
      insert into public.wait_history
        (route_stop_id, weekday_type, hour, median, p25, p75, mean, std, sample_count, updated_at)
      values (new.route_stop_id, v_wd, v_hr, v_wait, v_wait, v_wait, v_wait, 0, 1, now())
      on conflict (route_stop_id, weekday_type, hour) do update set
        mean   = (1 - a) * public.wait_history.mean   + a * v_wait,
        median = (1 - a) * public.wait_history.median + a * v_wait,
        p25    = (1 - a) * public.wait_history.p25 + a * least(v_wait, public.wait_history.median),
        p75    = (1 - a) * public.wait_history.p75 + a * greatest(v_wait, public.wait_history.median),
        std    = sqrt(greatest(
                   (1 - a) * power(public.wait_history.std, 2)
                   + a * power(v_wait - public.wait_history.mean, 2), 0)),
        sample_count = public.wait_history.sample_count + 1,
        updated_at = now();
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_board_history on public.queue_sessions;
create trigger trg_board_history
  after update on public.queue_sessions
  for each row execute function public.on_board_update_history();

-- 3. compute_estimate with the prior wired in ----------------------------------
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

-- 4. refresh_estimates: recompute EVERY active tile (cheap at this scale) so
--    quiet tiles track the hourly prior instead of going stale.
create or replace function public.refresh_estimates()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  update public.queue_sessions
  set status = 'expired'
  where status = 'active' and started_at < now() - interval '90 minutes';

  for r in select id from public.route_stops where active loop
    perform public.compute_estimate(r.id);
  end loop;
end;
$$;
