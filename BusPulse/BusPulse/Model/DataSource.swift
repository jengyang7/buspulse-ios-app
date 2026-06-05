//
//  DataSource.swift
//  BusPulse
//
//  Abstraction so the UI doesn't care whether tiles come from seed data or a
//  real backend. `MockDataSource` wraps the ported SampleData (used by #Previews
//  and as the seed-then-replace fallback); `SupabaseDataSource` reads the live
//  backend. See BACKEND_DESIGN.md §7.
//

import Foundation

/// Network-wide live counters for the home banner (across all locations).
struct LiveActivity: Sendable, Equatable {
    var reports: Int   // boards fed back in the last hour
    var active: Int    // commuters timing a queue right now
}

protocol DataSource: Sendable {
    // Reads
    func loadLocations() async throws -> [Location]
    func loadTiles(locationId: String) async throws -> [RouteTile]
    /// Network-wide activity (all locations): boards in the last hour + active now.
    func liveActivity() async throws -> LiveActivity
    /// Recent completed waits (minutes, oldest→newest) for the detail sparkline.
    func recentWaits(routeStopId: String) async throws -> [Int]
    /// The signed-in user's account stats for the Profile screen.
    func loadProfileSummary() async throws -> UserProfile
    /// The user's most recent boarded trips (newest first), for the Profile list.
    func recentTrips() async throws -> [RecentTrip]
    /// Live LTA arrivals (next 3 per service) at a bus stop, filtered to `services`.
    func busArrivals(stopCode: String, services: [String]) async throws -> [BusArrival]
    /// Historical median wait (min) for a location's tiles, keyed
    /// [routeStopId: [hour: median]], for the given weekday type ("weekday"/"weekend").
    func loadHistory(locationId: String, weekdayType: String) async throws -> [String: [Int: Int]]
    /// Median boarded wait (min) per route per hour for a location on one calendar
    /// day (SG time), keyed [routeStopId: [hour: median]]. Powers the Stats
    /// today-vs-last-week chart (one line per route).
    func routeWaitByHour(locationId: String, date: Date) async throws -> [String: [Int: Int]]

    /// Emits once whenever any wait_estimates row changes, so the model can
    /// reload the visible tiles. Mock sources may never emit.
    func estimateChanges() -> AsyncStream<Void>

    // Auth
    func currentUserId() async -> String?
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String) async throws
    func signOut() async throws

    // Queue actions (RPCs)
    /// Opens a queue session and returns its id (for a later `board`).
    func startQueue(routeStopId: String) async throws -> String
    func board(sessionId: String) async throws
}

/// Backed by the in-memory seed data ported from the prototype. Auth/actions
/// are no-ops so #Previews and offline runs behave as a signed-in user.
struct MockDataSource: DataSource {
    func loadLocations() async throws -> [Location] { SampleData.locations }
    func loadTiles(locationId: String) async throws -> [RouteTile] {
        SampleData.tiles(for: locationId)
    }
    func liveActivity() async throws -> LiveActivity {
        LiveActivity(reports: SampleData.allTiles.reduce(0) { $0 + $1.reports },
                     active: SampleData.allTiles.reduce(0) { $0 + $1.activeCount })
    }
    func recentWaits(routeStopId: String) async throws -> [Int] { [] }
    func loadProfileSummary() async throws -> UserProfile {
        UserProfile(name: "Jayden Kong", email: "jayden@buspulse.app",
                    rewardPoints: SampleData.rewardPoints,
                    tripsLogged: 42, reportsShared: 318, avgWaitMin: 17)
    }
    func recentTrips() async throws -> [RecentTrip] { SampleData.recentTrips }
    func busArrivals(stopCode: String, services: [String]) async throws -> [BusArrival] { [] }
    func loadHistory(locationId: String, weekdayType: String) async throws -> [String: [Int: Int]] { [:] }
    func routeWaitByHour(locationId: String, date: Date) async throws -> [String: [Int: Int]] {
        // Synthetic per-route curves (varied by date + route) for previews/offline.
        let seed = Int(date.timeIntervalSince1970 / 86_400) % 7
        var out: [String: [Int: Int]] = [:]
        for tile in SampleData.tiles(for: locationId) {
            let lift = (tile.low + tile.high) / 2
            var map: [Int: Int] = [:]
            for h in 5...23 {
                let peak = (h >= 7 && h <= 9) || (h >= 17 && h <= 20)
                let base = (peak ? lift + 6 : lift)
                map[h] = max(4, base + ((h * 3 + seed * 5) % 7) - 3)
            }
            out[tile.id] = map
        }
        return out
    }
    func estimateChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }            // static data — never changes
    }

    func currentUserId() async -> String? { "mock-user" }
    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String) async throws {}
    func signOut() async throws {}
    func startQueue(routeStopId: String) async throws -> String { UUID().uuidString }
    func board(sessionId: String) async throws {}
}
