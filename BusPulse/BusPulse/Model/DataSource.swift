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

protocol DataSource: Sendable {
    // Reads
    func loadLocations() async throws -> [Location]
    func loadTiles(locationId: String) async throws -> [RouteTile]
    /// Recent completed waits (minutes, oldest→newest) for the detail sparkline.
    func recentWaits(routeStopId: String) async throws -> [Int]

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
    func recentWaits(routeStopId: String) async throws -> [Int] { [] }
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
