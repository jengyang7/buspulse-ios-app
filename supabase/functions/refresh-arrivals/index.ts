// refresh-arrivals — scheduled poller that writes the soonest boardable LTA
// arrival per route_stop, so compute_estimate can floor the wait estimate by it.
//
// Invoked by pg_cron (internal). Guarded by a shared x-cron-secret header rather
// than a JWT (verify_jwt = false). Uses the service role to read/write the DB.
//
// Secrets required: LTA_ACCOUNT_KEY, CRON_SECRET.
// Auto-injected by the platform: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const LTA_URL = "https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival";

interface Eta { min: number | null; packed: boolean }
interface RouteStop { id: string; lines: string[]; lta_stop_code: string }

function minutesUntil(iso: string | undefined): number | null {
  if (!iso) return null;
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return null;
  return Math.max(0, Math.round((t - Date.now()) / 60000));
}

// Fetch a stop once → map of ServiceNo → its next ETAs (with packed flag).
async function fetchStop(code: string, key: string): Promise<Map<string, Eta[]>> {
  const res = await fetch(`${LTA_URL}?BusStopCode=${encodeURIComponent(code)}`, {
    headers: { AccountKey: key, accept: "application/json" },
  });
  const out = new Map<string, Eta[]>();
  if (!res.ok) return out;
  const data = await res.json();
  for (const s of data.Services ?? []) {
    out.set(s.ServiceNo, [s.NextBus, s.NextBus2, s.NextBus3].map((b) => ({
      min: minutesUntil(b?.EstimatedArrival),
      packed: b?.Load === "LSD",
    })));
  }
  return out;
}

// Soonest boardable arrival across the given services: prefer buses that aren't
// packed, fall back to the very soonest.
function soonest(services: string[], stop: Map<string, Eta[]>): number | null {
  const etas: Eta[] = [];
  for (const svc of services) etas.push(...(stop.get(svc) ?? []));
  const notPacked = etas.filter((e) => !e.packed && e.min !== null).map((e) => e.min!);
  if (notPacked.length) return Math.min(...notPacked);
  const any = etas.filter((e) => e.min !== null).map((e) => e.min!);
  return any.length ? Math.min(...any) : null;
}

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }
  const ltaKey = Deno.env.get("LTA_ACCOUNT_KEY");
  const supaUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!ltaKey || !supaUrl || !serviceKey) {
    return new Response(JSON.stringify({ error: "missing env" }), { status: 500 });
  }
  const auth = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };

  // Stops to refresh.
  const rsRes = await fetch(
    `${supaUrl}/rest/v1/route_stops?select=id,lines,lta_stop_code&lta_stop_code=not.is.null&active=eq.true`,
    { headers: auth },
  );
  const stops: RouteStop[] = await rsRes.json();
  if (!Array.isArray(stops) || stops.length === 0) {
    return new Response(JSON.stringify({ updated: 0 }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  // Fetch each unique stop code once.
  const codes = [...new Set(stops.map((s) => s.lta_stop_code))];
  const byCode = new Map<string, Map<string, Eta[]>>();
  await Promise.all(codes.map(async (c) => byCode.set(c, await fetchStop(c, ltaKey))));

  // Write soonest arrival per route_stop.
  const now = new Date().toISOString();
  let updated = 0;
  await Promise.all(stops.map(async (rs) => {
    const next = soonest(rs.lines, byCode.get(rs.lta_stop_code) ?? new Map());
    if (next === null) return;
    const r = await fetch(`${supaUrl}/rest/v1/route_stops?id=eq.${rs.id}`, {
      method: "PATCH",
      headers: { ...auth, "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify({ next_arrival_min: next, next_arrival_at: now }),
    });
    if (r.ok) updated++;
  }));

  return new Response(JSON.stringify({ updated, codes: codes.length }), {
    headers: { "Content-Type": "application/json" },
  });
});
