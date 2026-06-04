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
    /// Historical median wait (min) for a location's tiles, keyed
    /// [routeStopId: [hour: median]], for the given weekday type ("weekday"/"weekend").
    func loadHistory(locationId: String, weekdayType: String) async throws -> [String: [Int: Int]]

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
    func loadHistory(locationId: String, weekdayType: String) async throws -> [String: [Int: Int]] { [:] }
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
