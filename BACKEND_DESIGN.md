# BusPulse — Algorithm & Backend Design

## 1. What we're actually building

Today the app is a pure front-end: `SampleData` holds fixed tiles, and the "intelligence" (`spark`, `confidence`, `liveRecorders`, `genWait`, the `(low+high)/2` estimate) is **deterministic synthetic math** standing in for a real system. The job is to replace that with:

1. **A real estimation algorithm** that turns a stream of individual queue reports into a live `[low, high]` wait range + crowd level + confidence per *(location, route)*.
2. **A Supabase backend** that ingests reports, runs that algorithm, and pushes live results to the iOS client.

The data model in `Models.swift` is already shaped for this (the CLAUDE.md note "structure it so a real API can replace `SampleData` later" is the hook). The server becomes the source of truth for `RouteTile`'s `low/high/crowd/next/reports/fresh`; the client keeps owning the local timer and theming.

---

## 2. The core estimation algorithm

### 2.1 What a report is — and the subtlety that drives the design

A report is a queue **session**: user taps *Queue* at `t_start`, taps *I've boarded* at `t_board`. The sample is `wait = t_board − t_start`.

The non-obvious part: **a freshly-completed report describes the queue as it was when that person *joined*, not now.** Someone who just boarded after 20 min tells you about conditions 20 min ago. So completed reports alone always *lag* reality. Two corrections fix this:

- **Recency-weight by boarding time**, with a short half-life, so stale samples fade fast.
- **Use in-progress sessions as censored observations.** People currently queued (started, not yet boarded) have an `elapsed` that is a *lower bound* on the current wait. If 4 people have each been waiting 18+ min and nobody's boarded, the current wait is **≥ 18**, regardless of what completed reports say. This is the strongest "right now" signal and is what makes it a nowcast rather than a rear-view mirror.

### 2.2 Inputs (for one *(location, route)* at query time `T`)

- **Completed** `R = {(t_board_i, wait_i)}` within lookback `W` (≈ 90 min).
- **Active/censored** `A = {elapsed_j = T − t_start_j}` for sessions still open.
- **Prior** `μ_h(T), σ_h(T)` — historical median/spread for this route at this weekday-type × hour (§3).

### 2.3 Weighting completed reports

```
age_i      = T − t_board_i
w_recency  = 0.5 ^ (age_i / H)              # H = half-life ≈ 10 min
w_quality  = reputation_i × geo_ok_i        # ∈ (0,1], §6
w_i        = w_recency × w_quality
n_eff      = Σ w_i                          # effective sample size
```

Drop implausible samples first: `wait < 0.5 min` or `wait > 90 min` (cap/winsorize).

### 2.4 Central estimate (robust + Bayesian + censored floor)

```
m       = weighted_median(wait_i, w_i)                       # robust to outliers
# shrink toward historical prior when data is thin:
shrunk  = (n_eff·m + k·μ_h) / (n_eff + k)                    # k ≈ 3 (prior strength)
# never below what live queuers already prove:
floor   = robust_high(elapsed_j)   e.g. P75 of active elapsed
estimate = max(shrunk, floor)
```

When `n_eff = 0`, `estimate → μ_h` (pure prior). As live data accumulates, the prior washes out. This gives graceful cold-start behaviour for free.

### 2.5 The `[low, high]` range

```
lowRaw  = weighted_p25(wait_i, w_i)
highRaw = weighted_p75(wait_i, w_i)
# widen toward prior band when uncertain:
α       = n_eff / (n_eff + k)
low     = round( α·lowRaw  + (1−α)·(μ_h − σ_h) )
high    = round( α·highRaw + (1−α)·(μ_h + σ_h) )
# constraints:
low  = clamp(low,  3, estimate)
high = max(high, estimate, low + MIN_BAND)                  # MIN_BAND ≈ 3 min
```

This is exactly the `low/high` the `RouteTile` already carries — so the client doesn't change.

### 2.6 Crowd level (replaces the hard-coded `crowd`)

Crowd = current wait relative to *this route's own normal*, nudged by live density:

```
ratio = estimate / μ_h(T)
crowd = ratio < 0.85 ? .low
      : ratio < 1.25 ? .med
      : .high
# escalate one level if active_count is unusually high for this stop
```

Using a per-route baseline avoids "long routes always look packed."

### 2.7 Confidence (replaces `confidence()` thresholds)

Drive off **weighted** sample size + freshness + agreement, not raw count:

```
fresh   = T − newest(t_board_i)
disp    = (high − low) / max(estimate,1)          # relative spread
confidence = (n_eff ≥ 12 && fresh ≤ 5m && disp ≤ 0.5) ? "High"
           : (n_eff ≥ 7  && fresh ≤ 15m)            ? "Good"
           :                                          "Building"
```

`liveRecorders = |A|` (real active count). `freshMin = fresh`. `reports = n_eff` (rounded) or raw count for display.

### 2.8 `nextBus` — out of scope of crowdsourcing

`next` is a *schedule* quantity, not a crowd quantity. v1: drop it or estimate from boarding-event cadence (median inter-board gap). Real fix: integrate operator GTFS/schedule later (§9, Phase 4). Cross-border operators (CW, Causeway Express) may not publish GTFS — flag as a research item.

---

## 3. Historical model (powers Stats and the prior)

Roll completed sessions into buckets and reuse them two ways:

```
wait_history(location_id, route_id, weekday_type, hour)
  → median, p25, p75, mean, std, sample_count, updated via EWMA over days
```

- **Stats screen** (replaces `genWait`): hourly bars = `median` per hour; *best windows* = hours with lowest median; *all-day average* = mean across hours. The `spark()` sparkline becomes the **real** last-N boarded waits for that route.
- **Live prior** `μ_h(T), σ_h(T)` = the bucket for *current* weekday-type × hour, used in §2.4–2.5.

Update with a streaming EWMA on each board (`α ≈ 0.1`) plus a nightly consolidation job. `weekday_type ∈ {weekday, weekend}` — cheaper than 7 days and matches the prototype's peak logic.

---

## 4. Data model (Postgres + PostGIS)

```sql
profiles(id→auth.users, display_name, email, reward_points, reputation,
         locale, settings jsonb, created_at)

operators(id, code, name, color_hex)

locations(id, name, side, direction, geom geography(Point), note)

routes(id, badge, operator_id, lines text[], destination)

route_stops(location_id, route_id, direction, active)     -- which routes serve a stop

queue_sessions(                                           -- THE report
  id, user_id, location_id, route_id,
  started_at, boarded_at, status,                         -- active|boarded|abandoned|expired
  started_geo geography, board_geo geography,
  source,                                                 -- manual|auto
  device_id, created_at)

wait_estimates(                                           -- computed snapshot (cache)
  location_id, route_id, low, high, estimate, crowd,
  confidence, n_eff, active_count, fresh_at, updated_at)

wait_history(location_id, route_id, weekday_type, hour,
  median, p25, p75, mean, std, sample_count, updated_at)

reward_ledger(id, user_id, delta, reason, queue_session_id, created_at)  -- append-only
```

Key indexes: `queue_sessions(location_id, route_id, boarded_at DESC)`; **partial** index `WHERE status='active'`; GiST on `locations.geom`. Enums for `side`, `direction`, `crowd_level`, `session_status`.

**RLS:** users insert/select **their own** `queue_sessions` and own `profiles`/`reward_ledger`; `wait_estimates` / `wait_history` / `locations` / `routes` world-readable. Points are written only by a `SECURITY DEFINER` function, never directly by clients.

---

## 5. Backend architecture (Supabase)

```
iOS (supabase-swift)
  ├─ Auth (email + Google OAuth) ──────────► Supabase Auth      → AuthView
  ├─ RPC / PostgREST (start_queue, board) ─► Postgres functions → ingest
  ├─ Realtime subscription on wait_estimates ◄─ push live tiles → LiveView
  └─ REST reads (get_live, get_stats) ─────► PostgREST / RPC

Postgres
  ├─ compute_estimate(loc, route)  SQL/PLpgSQL  (§2, weighted percentiles)
  ├─ pg_cron: refresh estimates ~30–60s; expire stale sessions; nightly rollup
  └─ PostGIS geo-fence validation

Edge Functions (Deno/TS): OAuth callback glue, anti-abuse scoring,
  heavy/awkward math if the SQL estimator grows unwieldy.
```

**Where the algorithm lives:** v1 in a Postgres function (close to the data, fast, weighted-percentile via window functions). If §2.4's censored-survival math outgrows SQL, move just the estimator into an Edge Function triggered by a DB webhook on each board + the cron tick. Keep the *interface* (`wait_estimates` row) stable so the client never notices.

**Realtime / push:** Supabase Realtime publishes row changes on `wait_estimates`. Client subscribes to the rows for the *selected location*; every recompute (on board, and on the cron tick that bumps the censored floor) pushes new tiles — driving the `LiveDot` live feel. `active_count` changes flow the same way for `liveRecorders`.

---

## 6. Report lifecycle, data quality & anti-abuse

**Lifecycle:** `start_queue` inserts an `active` session (bumps `active_count` → realtime) → client runs its existing local timer → `board` sets `boarded_at`, validates, awards points, recomputes estimate → realtime push. Minimize/background: rely on server `started_at` (the session stays active server-side and contributes as a censored sample even if the app is backgrounded). Cron auto-expires sessions open > 90 min.

**Quality gates (each also feeds `w_quality`):**
- **Geo-fence** — `ST_DWithin(geo, stop, R)` at start & board; outside → down-weight or flag.
- **Plausibility** — drop `wait < 30s` / `> 90 min`; winsorize the rest.
- **Rate limit** — one active session per user per stop; cap reports/user/hour.
- **Reputation** — new accounts down-weighted; consistent, geo-verified contributors up-weighted (`reputation` on profile).
- **Robust stats** — weighted median/IQR already blunt outliers and Sybil pushes.

**Rewards** (`reward_ledger`, append-only): points only for plausible, geo-verified, non-duplicate boards; bonus for first-reporter / under-sampled route; diminishing returns to deter farming. `profile.reward_points` is the cached sum. 🌿 copy unchanged.

---

## 7. Client integration (replacing `SampleData`)

- Introduce a `DataSource` protocol; today's `SampleData` becomes `MockDataSource`; add `SupabaseDataSource` (supabase-swift).
- `AppModel` gains `async` loaders + a Realtime subscription; `tiles`, `totalReports`, and the estimate fields come from `wait_estimates`. The estimate/progress *timer* math (`estimateSeconds`, `progress`) stays client-side, seeded by server `low/high`.
- `startQueue`/`board` call RPCs but keep the optimistic local timer; reconcile elapsed against server `started_at`.
- `AuthView` → real Supabase Auth (email + the existing Google button). Localization stays fully client-side.
- Offline: cache last `wait_estimates`; queue `board` actions and flush on reconnect.

---

## 8. Phasing

| Phase | Scope |
|-------|-------|
| **0 — Foundations** | Schema, RLS, auth, seed locations/routes, read path + Realtime serving static-ish estimates. Unblocks client wiring immediately. |
| **1 — Ingestion + v1 estimator** | `start_queue`/`board` RPCs, recency-weighted median (§2.3–2.5, no censoring yet), rewards. |
| **2 — True nowcast + Stats** | Censored active-queue floor, Bayesian prior, `wait_history` rollups, Stats screen + real sparkline. |
| **3 — Hardening** | Geo validation, reputation weighting, auto-expire, anti-farming. |
| **4 — Schedule & notifications** | GTFS `nextBus` (research cross-border feeds), push notifications ("queue likely cleared", "better route nearby"). |

---

## 9. Risks & open questions

- **Cold start / chicken-and-egg:** no users → no estimates → no reason to use it. Mitigate with schedule-based priors and seeded/staff reports per stop until density builds. The prior-shrinkage design (§2.4) is specifically chosen so a brand-new stop still shows a sane (wide, "Building") estimate.
- **Background timer accuracy:** trust server `started_at`, not on-device wall clock, for elapsed.
- **`nextBus` source:** cross-border operators may not publish GTFS — may stay schedule-table-driven or be dropped in v1.
- **Privacy/retention:** store coarse geo only; set a retention window on raw `queue_sessions` after they're rolled into `wait_history`.
- **Testing the estimator:** port the determinism of `genWait` into *fixture-driven unit tests* — feed synthetic report streams, assert `low/high/crowd/confidence`, including cold-start, all-censored, and outlier-attack cases.

---

## 10. Design review — open issues to resolve before build

A review pass surfaced the following gaps. The censored-floor nowcast (§2.3) and Bayesian cold-start shrinkage (§2.4) hold up well; the items below are unresolved and ordered roughly by how much they affect correctness.

### 10.1 Bundled-route tiles vs. single `route_id` (model mismatch)
The SBS tile carries `lines: ["160","170X","170","950"]`, but `queue_sessions.route_id` is singular and estimates are per `(location, route)`. Undecided:
- What does a user "queue for the SBS family" write as `route_id` — the first bus that comes? A synthetic bundle id?
- How is one tile's `low/high/crowd` aggregated from several routes' estimates (min wait across the bundle? pooled samples?)?

Resolve the bundle semantics before the ingestion RPCs are designed — it changes the `route_stops` / `queue_sessions` shape.

### 10.2 Survivorship bias from abandonment
People who give up produce an `abandoned` session, not a completed `wait_i`. If long queues drive abandonment, the completed-sample pool is biased **low** exactly when waits are worst. The schema has the `abandoned` status but §2.3–2.5 never use it. Options: treat abandoned sessions as right-censored (lower bound = elapsed at abandonment, like active sessions), or model an abandonment hazard. At minimum, don't silently drop them.

### 10.3 Estimate oscillation / Realtime jitter
The censored floor ratchets the estimate **up** every cron tick while people wait, then drops **down** the instant someone boards — and each change pushes a Realtime row update. Without smoothing (hysteresis, EWMA on the published estimate, or a min-change threshold before pushing), tiles will sawtooth and the "live" feel degrades into jitter. Add an output-smoothing step between `compute_estimate` and the `wait_estimates` upsert.

### 10.4 Weighted percentiles are not free in SQL
Postgres has no built-in weighted `percentile_cont`. The §2 "weighted-percentile via window functions" needs a custom aggregate or row-expansion. This — not raw CPU load — is the real reason to move the estimator into a TS Edge Function sooner rather than later. (At current scale, ~15 `(location,route)` pairs recomputed every 30–60s is otherwise trivial for Postgres; CPU is not the bottleneck.)

### 10.5 Reward corrupts the measured signal
Points are paid for `board` — the exact event used as ground truth. Anti-abuse (§6) blunts Sybil/farming, but the structural tension remains: the incentive sits on the data path. Keep rewards tied to *server-observed, geo-verified, end-to-end* lifecycles only (see §10.6).

### 10.6 Offline `t_start` on the Causeway (network deadzone)
§6/§9 say "trust server `started_at`," but a user who taps *Queue* while offline mid-causeway gives the server no start until reconnect — so `started_at` would be the *arrival* time and undercount the wait. Resolution:
- Client records a **monotonic-clock elapsed duration** locally (not a wall-clock instant); on reconnect, sends `elapsed_so_far` and the server sets `started_at = now − elapsed`. A monotonic clock resists trivial date-rollback spoofing (signing a wall-clock timestamp does not — it only authenticates a possibly-skewed value).
- **Bound the trust:** cap any offline-reconciled wait at route P95 + margin, and **down-weight** offline-started sessions in `w_quality`.
- Cross-check **board geo** even when start was offline.
- Offline-path boards earn **reduced/no points**; full points only when the lifecycle was server-observed throughout. Removes the farming incentive on the unverifiable path.

### 10.7 GPS in concrete complexes
Woodlands Checkpoint and JB CIQ are large covered structures; GPS multipath/drift is expected. Geo-gating should **down-weight, not hard-reject** (the §6 wording already allows this — make it explicit and pick a generous radius). Note: reading Wi-Fi SSID as a fallback location signal is impractical on iOS (entitlement-gated and progressively locked down) — prefer coarse cell/region or lenient radius instead.
