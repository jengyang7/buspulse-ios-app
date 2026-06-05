#!/usr/bin/env bash
# Find LTA DataMall BusStopCodes by name, so you can map them onto route_stops.
#
# Usage:
#   LTA_ACCOUNT_KEY=your-key ./find_lta_stops.sh Kranji Woodlands Larkin
#
# Prints:  <BusStopCode>  <RoadName>  <Description>
# Then set them, e.g.:
#   supabase db query --local \
#     "update public.route_stops set lta_stop_code='45009'
#        where location_id='kranji' and route_id='<route-uuid>';"
#
# Requires: curl, jq.  (LTA paginates BusStops 500 at a time.)
set -euo pipefail

key="${LTA_ACCOUNT_KEY:?set LTA_ACCOUNT_KEY to your DataMall AccountKey}"
[ "$#" -ge 1 ] || { echo "usage: $0 <name> [<name>...]" >&2; exit 1; }

# Build a case-insensitive alternation from the search terms.
pattern="$(printf '%s|' "$@" | sed 's/|$//')"

skip=0
printf "%-8s  %-22s  %s\n" "CODE" "ROAD" "DESCRIPTION"
while :; do
  resp="$(curl -fsS -H "AccountKey: $key" -H "accept: application/json" \
    "https://datamall2.mytransport.sg/ltaodataservice/BusStops?\$skip=$skip")"
  n="$(printf '%s' "$resp" | jq '.value | length')"
  printf '%s' "$resp" \
    | jq -r '.value[] | "\(.BusStopCode)\t\(.RoadName)\t\(.Description)"' \
    | grep -iE "$pattern" \
    | awk -F'\t' '{ printf "%-8s  %-22s  %s\n", $1, $2, $3 }' || true
  [ "$n" -lt 500 ] && break
  skip=$((skip + 500))
done
