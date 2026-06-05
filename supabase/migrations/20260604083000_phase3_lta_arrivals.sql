-- Phase 3 — LTA DataMall live bus arrivals.
--
-- Each route_stop maps to one physical LTA bus stop (BusStopCode) so the route
-- page can show next-3 arrivals for the public services it bundles (160 / 170 /
-- 170X / 950). Cross-border operators (CW = Causeway Link, AC7 = Causeway
-- Express) aren't in DataMall, so their stops stay NULL and the app shows a
-- "not available for cross-border services" note instead.
--
-- The actual codes are filled per deployment (they're location-specific). Use
-- supabase/scenarios/find_lta_stops.sh to discover them, then UPDATE here or via
-- a follow-up migration.

alter table public.route_stops add column if not exists lta_stop_code text;

comment on column public.route_stops.lta_stop_code is
  'LTA DataMall BusStopCode for live arrivals. NULL for cross-border (CW/AC7) or '
  'unmapped stops — the app shows "not available" for those.';
