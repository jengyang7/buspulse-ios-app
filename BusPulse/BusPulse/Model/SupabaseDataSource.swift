//
//  SupabaseDataSource.swift
//  BusPulse
//
//  Live backend reads via Supabase PostgREST. Maps the joined
//  wait_estimates → route_stops → routes → operators rows into RouteTile, and
//  locations rows into Location. See BACKEND_DESIGN.md §5/§7.
//

import Foundation
import Supabase

/// Errors surfaced by the live data source (kept minimal — most failures bubble
/// up from the Supabase SDK directly).
enum SupabaseError: LocalizedError {
    case noProfile
    var errorDescription: String? {
        switch self {
        case .noProfile: "Couldn't load your profile."
        }
    }
}

struct SupabaseDataSource: DataSource {
    var client: SupabaseClient = SupabaseConfig.client

    // MARK: Locations

    private struct LocationRow: Decodable {
        let id: String
        let name: String
        let side: String
        let direction: String
        let note: String?
    }

    func loadLocations() async throws -> [Location] {
        let rows: [LocationRow] = try await client
            .from("locations")
            .select("id,name,side,direction,note")
            .execute()
            .value

        return rows.compactMap { r in
            guard let side = Side(rawValue: r.side),
                  let direction = Direction(rawValue: r.direction) else { return nil }
            return Location(id: r.id, name: r.name, side: side,
                            direction: direction, note: r.note ?? "")
        }
    }

    // MARK: Tiles (one wait_estimates row per tile, with its joins)

    private struct EstimateRow: Decodable {
        let low: Int
        let high: Int
        let estimate: Int
        let crowd: String
        let confidence: String
        let n_eff: Double
        let active_count: Int
        let updated_at: String?
        let route_stops: RouteStopRow
    }
    private struct RouteStopRow: Decodable {
        let id: String
        let lines: [String]
        let destination: String
        let lta_stop_code: String?
        let routes: RouteRow
    }
    private struct RouteRow: Decodable {
        let badge: String
        let operators: OperatorRow
    }
    private struct OperatorRow: Decodable {
        let name: String
        let color_hex: String
    }

    func loadTiles(locationId: String) async throws -> [RouteTile] {
        let rows: [EstimateRow] = try await client
            .from("wait_estimates")
            .select("""
                low,high,estimate,crowd,confidence,n_eff,active_count,updated_at,\
                route_stops!inner(id,lines,destination,location_id,active,lta_stop_code,\
                routes!inner(badge,operators!inner(name,color_hex)))
                """)
            .eq("route_stops.location_id", value: locationId)
            .eq("route_stops.active", value: true)
            .execute()
            .value

        return rows.map { r in
            RouteTile(
                id: r.route_stops.id,
                badge: r.route_stops.routes.badge,
                lines: r.route_stops.lines,
                colorHex: r.route_stops.routes.operators.color_hex,
                op: r.route_stops.routes.operators.name,
                to: r.route_stops.destination,
                low: r.low,
                high: r.high,
                crowd: CrowdLevel(rawValue: r.crowd) ?? .med,
                next: 0,                                   // nextBus is out of scope (§2.8)
                reports: Int(r.n_eff.rounded()),
                fresh: Self.secondsSince(r.updated_at),
                estimate: r.estimate,
                confidence: r.confidence,
                activeCount: r.active_count,
                ltaStopCode: r.route_stops.lta_stop_code
            )
        }
    }

    // MARK: Live bus arrivals (LTA DataMall via edge function)

    private struct ArrivalsRequest: Encodable { let stop_code: String; let services: [String] }
    private struct ArrivalsResponse: Decodable { let arrivals: [ArrivalDTO] }
    private struct ArrivalDTO: Decodable { let service: String; let etas: [EtaDTO] }
    private struct EtaDTO: Decodable { let min: Int?; let load: String }

    func busArrivals(stopCode: String, services: [String]) async throws -> [BusArrival] {
        let res: ArrivalsResponse = try await client.functions.invoke(
            "bus-arrivals",
            options: FunctionInvokeOptions(
                body: ArrivalsRequest(stop_code: stopCode, services: services))
        )
        return res.arrivals.map { dto in
            BusArrival(service: dto.service,
                       etas: dto.etas.map { ArrivalEta(minutes: $0.min,
                                                       load: BusLoad(rawValue: $0.load) ?? .unknown) })
        }
    }

    // MARK: Live activity (network-wide banner counters)

    private struct ActivityRow: Decodable { let reports: Int; let active: Int }

    func liveActivity() async throws -> LiveActivity {
        // `live_activity()` is a SECURITY DEFINER function returning a single
        // row; PostgREST surfaces it as a one-element array.
        let rows: [ActivityRow] = try await client
            .rpc("live_activity")
            .execute()
            .value
        let r = rows.first
        return LiveActivity(reports: r?.reports ?? 0, active: r?.active ?? 0)
    }

    // MARK: Recent boarded waits (real sparkline for the detail screen)

    private struct WaitRow: Decodable { let started_at: String; let boarded_at: String }

    /// The last up-to-9 completed waits (minutes) for a tile, oldest→newest.
    func recentWaits(routeStopId: String) async throws -> [Int] {
        let rows: [WaitRow] = try await client
            .from("queue_sessions")
            .select("started_at,boarded_at")
            .eq("route_stop_id", value: routeStopId)
            .eq("status", value: "boarded")
            .order("boarded_at", ascending: false)
            .limit(9)
            .execute()
            .value

        return rows.reversed().compactMap { r in
            guard let s = Self.parseDate(r.started_at), let b = Self.parseDate(r.boarded_at)
            else { return nil }
            return max(1, Int(b.timeIntervalSince(s) / 60))
        }
    }

    // MARK: Profile summary (account screen stats)

    private struct ProfileSummaryRow: Decodable {
        let display_name: String?
        let email: String?
        let reward_points: Int
        let trips_logged: Int
        let reports_shared: Int
        let avg_wait_min: Int
    }

    func loadProfileSummary() async throws -> UserProfile {
        // `profile_summary()` is SECURITY DEFINER and scopes to auth.uid(); it
        // returns a single row, surfaced by PostgREST as a one-element array.
        let rows: [ProfileSummaryRow] = try await client
            .rpc("profile_summary")
            .execute()
            .value
        guard let r = rows.first else { throw SupabaseError.noProfile }
        let fallbackName = r.email.map { String($0.prefix { $0 != "@" }) } ?? "Rider"
        return UserProfile(
            name: r.display_name ?? fallbackName,
            email: r.email ?? "",
            rewardPoints: r.reward_points,
            tripsLogged: r.trips_logged,
            reportsShared: r.reports_shared,
            avgWaitMin: r.avg_wait_min
        )
    }

    // MARK: Recent trips (boarded sessions, profile list)

    private struct TripRow: Decodable {
        let started_at: String
        let boarded_at: String?
        let route_stops: TripStopRow
    }
    private struct TripStopRow: Decodable {
        let destination: String
        let routes: TripRouteRow
    }
    private struct TripRouteRow: Decodable {
        let badge: String
        let operators: TripOperatorRow
    }
    private struct TripOperatorRow: Decodable {
        let name: String
        let color_hex: String
    }

    func recentTrips() async throws -> [RecentTrip] {
        // RLS scopes queue_sessions to the owner, so this is already the user's trips.
        let rows: [TripRow] = try await client
            .from("queue_sessions")
            .select("""
                started_at,boarded_at,\
                route_stops!inner(destination,\
                routes!inner(badge,operators!inner(name,color_hex)))
                """)
            .eq("status", value: "boarded")
            .order("boarded_at", ascending: false)
            .limit(8)
            .execute()
            .value

        return rows.compactMap { r in
            guard let boardedStr = r.boarded_at,
                  let boarded = Self.parseDate(boardedStr),
                  let started = Self.parseDate(r.started_at) else { return nil }
            let wait = max(1, Int(boarded.timeIntervalSince(started) / 60))
            return RecentTrip(
                badge: r.route_stops.routes.badge,
                colorHex: r.route_stops.routes.operators.color_hex,
                op: r.route_stops.routes.operators.name,
                to: r.route_stops.destination,
                wait: "\(wait)m",
                when: Self.tripWhen(boarded)
            )
        }
    }

    /// "Today · 8:14am" / "Yesterday · 7:22pm" / "Mon · 5:45pm".
    private static func tripWhen(_ date: Date) -> String {
        let cal = Calendar.current
        let time = DateFormatter()
        time.dateFormat = "h:mma"
        time.amSymbol = "am"; time.pmSymbol = "pm"
        let clock = time.string(from: date)
        let day: String
        if cal.isDateInToday(date) { day = "Today" }
        else if cal.isDateInYesterday(date) { day = "Yesterday" }
        else {
            let wd = DateFormatter(); wd.dateFormat = "EEE"
            day = wd.string(from: date)
        }
        return "\(day) · \(clock)"
    }

    // MARK: History (Stats screen)

    private struct HistRow: Decodable {
        let route_stop_id: String
        let hour: Int
        let median: Double?
    }

    func loadHistory(locationId: String, weekdayType: String) async throws -> [String: [Int: Int]] {
        let rows: [HistRow] = try await client
            .from("wait_history")
            .select("route_stop_id,hour,median,route_stops!inner(location_id)")
            .eq("route_stops.location_id", value: locationId)
            .eq("weekday_type", value: weekdayType)
            .execute()
            .value

        var map: [String: [Int: Int]] = [:]
        for r in rows {
            guard let m = r.median else { continue }
            map[r.route_stop_id, default: [:]][r.hour] = Int(m.rounded())
        }
        return map
    }

    // MARK: Per-route, per-hour wait curve (Stats today-vs-last-week chart)

    private struct WaitHourRow: Decodable {
        let route_stop_id: String
        let hour: Int
        let wait: Int
        let sample_count: Int
    }

    func routeWaitByHour(locationId: String, date: Date) async throws -> [String: [Int: Int]] {
        let rows: [WaitHourRow] = try await client
            .rpc("route_wait_by_hour",
                 params: ["p_location_id": locationId, "p_date": Self.sgDateString(date)])
            .execute()
            .value
        var out: [String: [Int: Int]] = [:]
        for r in rows { out[r.route_stop_id, default: [:]][r.hour] = r.wait }
        return out
    }

    /// "yyyy-MM-dd" for `date` in Singapore local time — the calendar day the RPC buckets by.
    private static func sgDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Singapore")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func parseDate(_ iso: String) -> Date? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f1.date(from: iso) ?? f2.date(from: iso)
    }

    // MARK: Auth

    func currentUserId() async -> String? {
        do { return try await client.auth.session.user.id.uuidString }
        catch { return nil }
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        try await client.auth.signUp(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: Queue actions (Postgres functions via RPC)

    private struct SessionRow: Decodable { let id: String }

    func startQueue(routeStopId: String) async throws -> String {
        let row: SessionRow = try await client
            .rpc("start_queue", params: ["p_route_stop_id": routeStopId])
            .execute()
            .value
        return row.id
    }

    func board(sessionId: String) async throws {
        try await client
            .rpc("board", params: ["p_session_id": sessionId])
            .execute()
    }

    // MARK: Realtime

    /// Subscribes to all wait_estimates row changes and emits `()` on each.
    /// The model reloads the currently-visible location on every emit.
    func estimateChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                let channel = client.realtimeV2.channel("public:wait_estimates")
                let changes = channel.postgresChange(
                    AnyAction.self, schema: "public", table: "wait_estimates")
                await channel.subscribe()
                for await _ in changes {
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Seconds elapsed since an ISO-8601 timestamp string, tolerant of the
    /// micro/millisecond fractional forms Postgres emits. 0 if absent/unparseable.
    private static func secondsSince(_ iso: String?) -> Int {
        guard let iso else { return 0 }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let date = withFrac.date(from: iso) ?? plain.date(from: iso)
        guard let date else { return 0 }
        return max(0, Int(Date().timeIntervalSince(date)))
    }
}
