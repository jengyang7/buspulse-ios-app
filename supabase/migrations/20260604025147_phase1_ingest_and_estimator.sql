-- Phase 1 — Ingestion RPCs + v1 estimator.
-- See BACKEND_DESIGN.md §2 (algorithm) and §6 (lifecycle).
--
-- Scope vs the doc's phasing: this is the v1 estimator (§2.3–2.5) — recency-
-- weighted percentiles over completed reports — PLUS the censored active-queue
-- floor (§2.3), which the doc nominally defers to Phase 2 but which is included
-- here because it is the signal that lets *currently-queuing* users move the
-- estimate. The Bayesian prior / wait_history shrinkage and the per-route crowd
-- baseline remain Phase 2 (crowd uses placeholder absolute thresholds for now,
-- flagged inline).

-- Tunables (kept inline as literals; promote to a config table later) ----------
--   W       lookback window for completed reports ... 90 min
--   H       recency half-life ......................... 10 min
--   MIN_BAND minimum [low,high] width ................. 3 min
--   BOARD_POINTS reward per valid board .............. 10

-- Weighted percentile over a route_stop's recent completed waits ---------------
-- Returns the smallest wait whose cumulative recency-weight reaches p·Σw.
create or replace function public.completed_wpctl(p_route_stop_id uuid, p numeric)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  with c as (
    select
      extract(epoch from (boarded_at - started_at)) / 60.0 as wait_min,
      power(0.5, (extract(epoch from (now() - boarded_at)) / 60.0) / 10.0) as w
    from public.queue_sessions
    where route_stop_id = p_route_stop_id
      and status = 'boarded'
      and boarded_at >= now() - interval '90 minutes'
      and extract(epoch from (boarded_at - started_at)) / 60.0 between 0.5 and 90
  ),
  ranked as (
    select wait_min,
           sum(w) over (order by wait_min) as cum,
           sum(w) over ()                  as tot
    from c
  )
  select wait_min from ranked where cum >= p * tot order by cum limit 1;
$$;

-- Effective sample size = Σ recency weights over the lookback window ------------
create or replace function public.completed_neff(p_route_stop_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(
           power(0.5, (extract(epoch from (now() - boarded_at)) / 60.0) / 10.0)
         ), 0)
  from public.queue_sessions
  where route_stop_id = p_route_stop_id
    and status = 'boarded'
    and boarded_at >= now() - interval '90 minutes'
    and extract(epoch from (boarded_at - started_at)) / 60.0 between 0.5 and 90;
$$;

-- Recompute the wait_estimates snapshot for one tile (§2.3–2.7) ----------------
create or replace function public.compute_estimate(p_route_stop_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m        numeric;   -- weighted median of completed waits
  v_low_raw  numeric;   -- weighted p25
  v_high_raw numeric;   -- weighted p75
  v_neff     numeric;
  v_floor    numeric;   -- P75 of active elapsed (censored lower bound)
  v_active   integer;
  v_fresh    timestamptz;
  v_est      numeric;
  v_low      integer;
  v_high     integer;
  v_crowd    public.crowd_level;
  v_conf     text;
  v_fresh_min numeric;
  v_disp     numeric;
begin
  v_m        := public.completed_wpctl(p_route_stop_id, 0.5);
  v_low_raw  := public.completed_wpctl(p_route_stop_id, 0.25);
  v_high_raw := public.completed_wpctl(p_route_stop_id, 0.75);
  v_neff     := public.completed_neff(p_route_stop_id);

  -- Censored floor: people currently queued prove the wait is at least this.
  select
    percentile_cont(0.75) within group (
      order by extract(epoch from (now() - started_at)) / 60.0),
    count(*)
  into v_floor, v_active
  from public.queue_sessions
  where route_stop_id = p_route_stop_id and status = 'active';

  select max(boarded_at) into v_fresh
  from public.queue_sessions
  where route_stop_id = p_route_stop_id and status = 'boarded'
    and boarded_at >= now() - interval '90 minutes';

  -- Nothing to say yet: leave any existing snapshot untouched.
  if coalesce(v_neff, 0) = 0 and coalesce(v_active, 0) = 0 then
    return;
  end if;

  -- Central estimate = max(weighted median, censored floor). (Prior shrinkage
  -- is Phase 2; with no completed data we fall back to the floor.)
  v_est := greatest(coalesce(v_m, 0), coalesce(v_floor, 0));

  v_low  := round(coalesce(v_low_raw, greatest(v_est - 3, 3)));
  v_high := round(coalesce(v_high_raw, v_est));
  v_low  := greatest(least(v_low, round(v_est)), 3);          -- clamp(low, 3, est)
  v_high := greatest(v_high, round(v_est), v_low + 3);        -- max(high, est, low+MIN_BAND)

  -- Crowd: PLACEHOLDER absolute thresholds until wait_history gives a per-route
  -- baseline (§2.6 ratio = estimate / μ_h). TODO Phase 2.
  v_crowd := case
               when v_est < 10 then 'low'
               when v_est < 20 then 'med'
               else 'high'
             end::public.crowd_level;

  -- Confidence (§2.7): weighted n, freshness, agreement.
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

-- start_queue: open an active session for the caller (§6) ----------------------
-- One active session per (user, route_stop): returns the existing one if any.
create or replace function public.start_queue(
  p_route_stop_id uuid,
  p_lng double precision default null,
  p_lat double precision default null
)
returns public.queue_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.queue_sessions;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_row from public.queue_sessions
  where user_id = v_uid and route_stop_id = p_route_stop_id and status = 'active'
  limit 1;
  if found then
    return v_row;                                   -- idempotent
  end if;

  insert into public.queue_sessions (user_id, route_stop_id, started_geo)
  values (
    v_uid, p_route_stop_id,
    case when p_lng is not null and p_lat is not null
         then extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography
    end)
  returning * into v_row;

  -- A new active queuer raises the censored floor → refresh the tile.
  perform public.compute_estimate(p_route_stop_id);
  return v_row;
end;
$$;

-- board: close the caller's active session, award points, recompute (§6) -------
create or replace function public.board(
  p_session_id uuid,
  p_lng double precision default null,
  p_lat double precision default null
)
returns public.queue_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.queue_sessions;
  v_points integer := 10;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  update public.queue_sessions
  set status = 'boarded',
      boarded_at = now(),
      board_geo = case when p_lng is not null and p_lat is not null
        then extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography end
  where id = p_session_id and user_id = v_uid and status = 'active'
  returning * into v_row;

  if not found then
    raise exception 'no active session % for caller', p_session_id;
  end if;

  -- Award points (append-only ledger + cached profile sum). Plausibility /
  -- geo / anti-farming gates are Phase 3; v1 awards a flat amount.
  insert into public.reward_ledger (user_id, delta, reason, queue_session_id)
  values (v_uid, v_points, 'board', v_row.id);
  update public.profiles set reward_points = reward_points + v_points
  where id = v_uid;

  perform public.compute_estimate(v_row.route_stop_id);
  return v_row;
end;
$$;

-- Let signed-in users call the RPCs (function bodies run as definer) -----------
grant execute on function public.start_queue(uuid, double precision, double precision) to authenticated;
grant execute on function public.board(uuid, double precision, double precision)        to authenticated;
