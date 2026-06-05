// bus-arrivals — proxy to LTA DataMall Bus Arrival v3.
//
// Keeps the LTA AccountKey server-side (never in the app). The client sends a
// BusStopCode and the service numbers it cares about; we return the next-3
// arrivals per service as minutes-from-now plus a normalized crowding load.
//
// Request  (POST JSON): { "stop_code": "45009", "services": ["160","170X"] }
// Response (JSON):      { "arrivals": [ { "service":"160",
//                          "etas":[ {"min":3,"load":"low"}, {"min":11,"load":"med"},
//                                   {"min":null,"load":"unknown"} ] } ] }
//
// Secret required:  LTA_ACCOUNT_KEY  (set via `supabase secrets set` or the
// local supabase/functions/.env file).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const LTA_URL =
  "https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// LTA Load codes → our crowd levels.
function load(code: string | undefined): "low" | "med" | "high" | "unknown" {
  switch (code) {
    case "SEA": return "low";   // Seats Available
    case "SDA": return "med";   // Standing Available
    case "LSD": return "high";  // Limited Standing
    default:    return "unknown";
  }
}

// ISO timestamp → whole minutes from now (clamped at 0); null if absent/empty.
function minutesUntil(iso: string | undefined): number | null {
  if (!iso) return null;
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return null;
  return Math.max(0, Math.round((t - Date.now()) / 60000));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const key = Deno.env.get("LTA_ACCOUNT_KEY");
  if (!key) {
    return new Response(
      JSON.stringify({ error: "LTA_ACCOUNT_KEY not configured" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  let stopCode = "";
  let services: string[] = [];
  try {
    const body = await req.json();
    stopCode = String(body.stop_code ?? "").trim();
    services = Array.isArray(body.services) ? body.services.map(String) : [];
  } catch {
    /* fall through to validation below */
  }
  if (!stopCode) {
    return new Response(JSON.stringify({ error: "stop_code is required" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const ltaRes = await fetch(`${LTA_URL}?BusStopCode=${encodeURIComponent(stopCode)}`, {
    headers: { AccountKey: key, accept: "application/json" },
  });
  if (!ltaRes.ok) {
    return new Response(
      JSON.stringify({ error: `LTA error ${ltaRes.status}` }),
      { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const data = await ltaRes.json();
  const wanted = new Set(services);
  const arrivals = (data.Services ?? [])
    .filter((s: { ServiceNo: string }) => wanted.size === 0 || wanted.has(s.ServiceNo))
    .map((s: Record<string, { EstimatedArrival?: string; Load?: string }>) => ({
      service: (s as unknown as { ServiceNo: string }).ServiceNo,
      etas: [s.NextBus, s.NextBus2, s.NextBus3].map((b) => ({
        min: minutesUntil(b?.EstimatedArrival),
        load: load(b?.Load),
      })),
    }));

  return new Response(JSON.stringify({ arrivals }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
