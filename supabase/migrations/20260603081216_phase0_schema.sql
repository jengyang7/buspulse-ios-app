-- Phase 0 — Foundations: extensions, enums, tables, indexes.
-- See BACKEND_DESIGN.md §4 (data model) and §10.1 (route_stop = tile).
--
-- Deviation from §4 as written: `lines[]` and `destination` live on
-- route_stops, not routes, because the seed data shows the same badge serves
-- different line sets / destinations at different stops. A route_stop row
-- therefore IS one client tile, and wait_estimates keys off route_stop_id.

-- Extensions ------------------------------------------------------------------
create extension if not exists postgis with schema extensions;

-- Enums -----------------------------------------------------------------------
create type side           as enum ('SG', 'MY');
create type direction      as enum ('SG-MY', 'MY-SG');
create type crowd_level    as enum ('low', 'med', 'high');
create type session_status as enum ('active', 'boarded', 'abandoned', 'expired');
create type session_source as enum ('manual', 'auto');

-- Profiles --------------------------------------------------------------------
-- 1:1 with auth.users (row auto-created by trigger in the next migration).
create table profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text,
  email         text,
  reward_points integer     not null default 0,
  reputation    real        not null default 0.5,  -- ∈ (0,1], feeds w_quality (§6)
  locale        text        not null default 'en',
  settings      jsonb       not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);

-- Operators -------------------------------------------------------------------
create table operators (
  id        text primary key,            -- slug, e.g. 'causeway_link'
  code      text not null unique,        -- short badge family, e.g. 'CW'
  name      text not null,               -- display name, e.g. 'Causeway Link'
  color_hex text not null                -- operator colour, e.g. '#F2C200'
);

-- Locations -------------------------------------------------------------------
create table locations (
  id        text primary key,            -- slug, e.g. 'woodlands_ckpt'
  name      text not null,
  side      side not null,
  direction direction not null,
  geom      geography(Point, 4326),      -- stop centroid for geo-fencing (§6)
  note      text
);

-- Routes ----------------------------------------------------------------------
-- Operator-level badge identity only. Location-specific line sets and
-- destinations live on route_stops (see header note).
create table routes (
  id          text primary key,          -- slug, e.g. 'sbs', 'cw', 'ac7', '950'
  badge       text not null,             -- chip label, e.g. 'SBS'
  operator_id text not null references operators (id)
);

-- Route ↔ stop (one row per client tile) --------------------------------------
create table route_stops (
  id          uuid primary key default gen_random_uuid(),
  location_id text not null references locations (id) on delete cascade,
  route_id    text not null references routes (id)   on delete cascade,
  direction   direction not null,
  lines       text[]  not null default '{}',         -- constituent line numbers
  destination text    not null,                       -- "to" shown on the tile
  active      boolean not null default true,
  unique (location_id, route_id, direction)
);

-- Queue sessions — THE report (§2.1, §6 lifecycle) ----------------------------
create table queue_sessions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  route_stop_id uuid not null references route_stops (id) on delete cascade,
  status        session_status not null default 'active',
  started_at    timestamptz not null default now(),
  boarded_at    timestamptz,
  started_geo   geography(Point, 4326),
  board_geo     geography(Point, 4326),
  source        session_source not null default 'manual',
  device_id     text,
  created_at    timestamptz not null default now()
);

-- Computed snapshot / cache served to the client (§2, §5 realtime) ------------
create table wait_estimates (
  route_stop_id uuid primary key references route_stops (id) on delete cascade,
  low           integer not null,
  high          integer not null,
  estimate      integer not null,
  crowd         crowd_level not null,
  confidence    text not null default 'Building',
  n_eff         real not null default 0,
  active_count  integer not null default 0,
  fresh_at      timestamptz,             -- timestamp of newest contributing board
  updated_at    timestamptz not null default now()
);

-- Historical rollups powering Stats + the live prior (§3) ---------------------
create table wait_history (
  route_stop_id uuid not null references route_stops (id) on delete cascade,
  weekday_type  text not null,           -- 'weekday' | 'weekend'
  hour          smallint not null,       -- 0..23
  median        real,
  p25           real,
  p75           real,
  mean          real,
  std           real,
  sample_count  integer not null default 0,
  updated_at    timestamptz not null default now(),
  primary key (route_stop_id, weekday_type, hour)
);

-- Append-only points ledger (§6) ---------------------------------------------
create table reward_ledger (
  id               bigint generated always as identity primary key,
  user_id          uuid not null references auth.users (id) on delete cascade,
  delta            integer not null,
  reason           text not null,
  queue_session_id uuid references queue_sessions (id) on delete set null,
  created_at       timestamptz not null default now()
);

-- Indexes ---------------------------------------------------------------------
-- Hot lookup: recent completed reports for a tile (§2.2 lookback window).
create index queue_sessions_boarded_idx
  on queue_sessions (route_stop_id, boarded_at desc);

-- Censored-observation pool: only open sessions matter (§2.3). Partial index.
create index queue_sessions_active_idx
  on queue_sessions (route_stop_id)
  where status = 'active';

create index queue_sessions_user_idx  on queue_sessions (user_id);
create index reward_ledger_user_idx   on reward_ledger (user_id);
create index route_stops_location_idx on route_stops (location_id) where active;

-- Spatial index for geo-fence validation (§6).
create index locations_geom_idx on locations using gist (geom);
