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
                route_stops!inner(id,lines,destination,location_id,active,\
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
                activeCount: r.active_count
            )
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
