-- Phase 0 seed — ported from BusPulse/BusPulse/Model/SampleData.swift.
-- Operators, routes, locations, one route_stop per tile, and a static
-- wait_estimates snapshot so the read path + Realtime have data to serve
-- before the estimator (Phase 1) exists.

-- Operators -------------------------------------------------------------------
insert into operators (id, code, name, color_hex) values
  ('causeway_express', 'AC7', 'Causeway Express', '#1F9E6B'),
  ('causeway_link',    'CW',  'Causeway Link',    '#F2C200'),
  ('sbs',              'SBS', 'SBS Transit',      '#7C5CFF'),
  ('smrt',             '950', 'SMRT',             '#E23B3B');

-- Routes (operator-level badge identity) --------------------------------------
insert into routes (id, badge, operator_id) values
  ('ac7', 'AC7', 'causeway_express'),
  ('cw',  'CW',  'causeway_link'),
  ('sbs', 'SBS', 'sbs'),
  ('950', '950', 'smrt');

-- Locations (geom = approximate stop centroid, lng/lat) -----------------------
insert into locations (id, name, side, direction, geom, note) values
  ('woodlands_ckpt', 'Woodlands Checkpoint',       'SG', 'SG-MY',
     extensions.st_setsrid(extensions.st_makepoint(103.7690, 1.4467), 4326)::geography, 'Departure bus bays'),
  ('kranji',         'Kranji MRT',                 'SG', 'SG-MY',
     extensions.st_setsrid(extensions.st_makepoint(103.7619, 1.4252), 4326)::geography, 'Bus berth A'),
  ('woodlands_ti',   'Woodlands Temp Interchange', 'SG', 'SG-MY',
     extensions.st_setsrid(extensions.st_makepoint(103.7865, 1.4360), 4326)::geography, 'Cross-border bays'),
  ('jbciq',          'JB Sentral CIQ',             'MY', 'MY-SG',
     extensions.st_setsrid(extensions.st_makepoint(103.7640, 1.4637), 4326)::geography, 'Level 1 boarding hall'),
  ('larkin',         'Larkin Terminal',            'MY', 'MY-SG',
     extensions.st_setsrid(extensions.st_makepoint(103.7414, 1.4927), 4326)::geography, 'Platform 2–4');

-- Route ↔ stop (one row per tile in SampleData.tiles) -------------------------
insert into route_stops (location_id, route_id, direction, lines, destination) values
  ('woodlands_ckpt', 'ac7', 'SG-MY', '{AC7}',                    'JB Sentral'),
  ('woodlands_ckpt', 'cw',  'SG-MY', '{CW}',                     'JB Sentral'),
  ('woodlands_ckpt', 'sbs', 'SG-MY', '{160,170X,170,950}',       'JB / Larkin'),
  ('kranji',         'cw',  'SG-MY', '{CW}',                     'JB Sentral'),
  ('kranji',         'sbs', 'SG-MY', '{160,170X}',               'JB Sentral / Larkin'),
  ('woodlands_ti',   '950', 'SG-MY', '{950}',                    'JB Sentral'),
  ('jbciq',          'ac7', 'MY-SG', '{AC7}',                    'Newton'),
  ('jbciq',          'cw',  'MY-SG', '{CW}',                     'Singapore'),
  ('jbciq',          'sbs', 'MY-SG', '{160,170X,170}',           'Queen St / Kranji'),
  ('jbciq',          '950', 'MY-SG', '{950}',                    'Woodlands'),
  ('larkin',         'cw',  'MY-SG', '{CW}',                     'Queen St'),
  ('larkin',         'sbs', 'MY-SG', '{170}',                    'Queen St');

-- Static wait_estimates snapshot ----------------------------------------------
-- low/high/crowd from SampleData; estimate = round((low+high)/2) [latestBoarded];
-- n_eff/active_count/confidence mirror the prototype's Estimate.* helpers;
-- fresh_at = now() - <fresh> minutes. Joined to route_stops by natural key.
insert into wait_estimates
  (route_stop_id, low, high, estimate, crowd, confidence, n_eff, active_count, fresh_at)
select rs.id, v.low, v.high, v.estimate, v.crowd::crowd_level, v.confidence,
       v.n_eff, v.active_count, now() - make_interval(mins => v.fresh)
from (values
  -- location,        route, low, high, est, crowd,  confidence, n_eff, active, fresh
  ('woodlands_ckpt', 'ac7',  5,  9,  7,  'low',  'Building',  6,  1, 3),
  ('woodlands_ckpt', 'cw',   6, 10,  8,  'low',  'High',     13,  2, 2),
  ('woodlands_ckpt', 'sbs', 14, 21, 18,  'med',  'High',     18,  3, 1),
  ('kranji',         'cw',   7, 12, 10,  'low',  'Good',      9,  2, 2),
  ('kranji',         'sbs',  9, 16, 13,  'med',  'Good',      9,  2, 3),
  ('woodlands_ti',   '950', 18, 25, 22,  'high', 'High',     16,  3, 2),
  ('jbciq',          'ac7',  8, 13, 11,  'low',  'Good',      7,  1, 3),
  ('jbciq',          'cw',  18, 26, 22,  'high', 'High',     24,  4, 1),
  ('jbciq',          'sbs', 22, 30, 26,  'high', 'High',     17,  3, 2),
  ('jbciq',          '950', 24, 33, 29,  'high', 'High',     19,  3, 4),
  ('larkin',         'cw',  11, 17, 14,  'med',  'Building',  6,  1, 5),
  ('larkin',         'sbs', 15, 23, 19,  'high', 'Good',     10,  2, 4)
) as v(location_id, route_id, low, high, estimate, crowd, confidence, n_eff, active_count, fresh)
join route_stops rs
  on rs.location_id = v.location_id and rs.route_id = v.route_id;

-- Real-world data corrections (LTA stop codes, bus sets, destinations).
-- Cross-border stops (CW / AC7) aren't in LTA DataMall, so they get no code.
update route_stops set lta_stop_code = '46109' where location_id = 'woodlands_ckpt' and route_id = 'sbs';
update route_stops set lta_stop_code = '45139' where location_id = 'kranji'         and route_id = 'sbs';
update route_stops set lta_stop_code = '47009' where location_id = 'woodlands_ti'   and route_id = '950';
update route_stops set lta_stop_code = '46219' where location_id = 'jbciq'          and route_id in ('sbs','950');
update route_stops set lta_stop_code = '46239' where location_id = 'larkin'         and route_id = 'sbs';

-- Kranji cross-border set heading to the Causeway: 160 / 170X / 170.
update route_stops set lines = array['160','170X','170'] where location_id = 'kranji' and route_id = 'sbs';

-- Destinations (immediate next major stop in the travel direction).
update route_stops set destination = 'Woodlands Checkpoint'       where location_id in ('kranji','jbciq');
update route_stops set destination = 'Woodlands Train Checkpoint' where location_id = 'woodlands_ti' and route_id = '950';
update route_stops set destination = 'JB Sentral CIQ'             where location_id = 'larkin';

-- Historical prior (Phase 2): seed a per-tile × weekday × hour baseline from the
-- estimates above, then recompute every tile so quiet tiles show the "typical
-- for this time" estimate immediately (not the static seed).
select seed_wait_history_baseline();
select compute_estimate(id) from route_stops;
