//
//  AppModel.swift
//  BusPulse
//
//  Single source of app state, ported from the prototype's useState hooks.
//

import SwiftUI
import Observation

enum AppTab: Hashable { case live, stats, profile, settings }

/// Full-screen flows pushed over the tab bar.
enum Flow: Hashable {
    case detail(RouteTile)
    case track
    case done
    case auth
}

@MainActor
@Observable
final class AppModel {

    // Navigation
    var tab: AppTab = .live
    var flow: Flow?                  // nil = showing the current tab

    // Live screen selection
    var direction: Direction = .sgToMy {
        didSet {
            selectedLocationId = firstLocationId(for: direction)
            reloadSelectedTiles()
        }
    }
    var selectedLocationId: String = SampleData.firstLocation(for: .sgToMy).id

    // Active queue
    private(set) var active: RouteTile?
    private(set) var elapsed: Int = 0        // seconds
    var minimized = false
    private var queueOrigin: Flow?           // where the queue was started from
    private var timerTask: Task<Void, Never>?
    private var sessionId: String?           // backend queue_sessions.id, if any

    // Auth UI state
    var authError: String?
    var authBusy = false

    // Settings / preferences
    var appearance: AppearanceMode = .dark
    var language: AppLanguage = .en
    var notificationsOn = true
    var locationAccessOn = true
    var autoDetectBoarding = true

    // Profile
    var profileName = "Jayden Kong"
    var profileEmail = "jayden@buspulse.app"

    var theme: Theme { appearance.theme }
    var colorScheme: ColorScheme { appearance == .dark ? .dark : .light }

    // MARK: - Data source

    private let dataSource: DataSource
    /// All known locations — seeded from SampleData, replaced by `load()`.
    var allLocations: [Location] = SampleData.locations
    /// Tiles keyed by location id — seeded from SampleData, replaced by `load()`.
    private var tilesByLocation: [String: [RouteTile]] = SampleData.tiles
    /// Non-nil when the last backend load failed (UI may surface it).
    var loadError: String?
    /// Network-wide counters for the home banner (all locations, last hour).
    var liveActivity = LiveActivity(
        reports: SampleData.allTiles.reduce(0) { $0 + $1.reports },
        active: SampleData.allTiles.reduce(0) { $0 + $1.activeCount }
    )

    init(dataSource: DataSource = MockDataSource()) {
        self.dataSource = dataSource
    }

    // MARK: - Derived

    var selectedLocation: Location {
        allLocations.first { $0.id == selectedLocationId }
            ?? SampleData.firstLocation(for: direction)
    }
    var tiles: [RouteTile] {
        (tilesByLocation[selectedLocationId] ?? []).sorted { $0.low < $1.low }
    }
    var totalReports: Int {
        (tilesByLocation[selectedLocationId] ?? []).reduce(0) { $0 + $1.reports }
    }
    var fastestTileId: String? {
        tiles.min(by: { $0.estimate < $1.estimate })?.id
    }

    func locations(for direction: Direction) -> [Location] {
        allLocations.filter { $0.direction == direction }
    }

    private func firstLocationId(for direction: Direction) -> String {
        locations(for: direction).first?.id ?? SampleData.firstLocation(for: direction).id
    }

    /// Mid-range estimate in seconds for the active queue.
    var estimateSeconds: Int {
        guard let a = active else { return 0 }
        return Int((Double(a.low + a.high) / 2).rounded()) * 60
    }
    /// Progress 0…1 of elapsed against the estimate.
    var progress: Double {
        estimateSeconds == 0 ? 0 : min(Double(elapsed) / Double(estimateSeconds), 1)
    }
    var isOvertime: Bool { active != nil && elapsed > estimateSeconds }

    // MARK: - Greeting

    var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<5:   "Good night"
        case 5..<12: "Good morning"
        case 12..<17:"Good afternoon"
        case 17..<21:"Good evening"
        default:     "Good night"
        }
    }

    // MARK: - Navigation actions

    func selectLocation(_ id: String) {
        selectedLocationId = id
        reloadSelectedTiles()
    }

    // MARK: - Data loading

    /// Fetch locations + tiles for the current selection, replacing seed data.
    /// Safe to call repeatedly; failures are captured in `loadError`.
    func load() async {
        // Gate on auth: no session → show the sign-in screen. Tiles are still
        // loaded below (they're public) so data is ready once the user signs in.
        if await dataSource.currentUserId() == nil {
            flow = .auth
        }
        do {
            let locs = try await dataSource.loadLocations()
            if !locs.isEmpty {
                allLocations = locs
                if !allLocations.contains(where: { $0.id == selectedLocationId }) {
                    selectedLocationId = firstLocationId(for: direction)
                }
            }
            try await loadTiles(for: selectedLocationId)
            await refreshLiveActivity()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        startLiveUpdates()
    }

    // MARK: Live updates

    private var realtimeTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    /// Keeps the visible tiles fresh two ways: a Realtime subscription for
    /// instant pushes, plus a periodic poll as a reliable fallback (the cron
    /// recomputes server-side every 30s). Both are started once and idempotent.
    private func startLiveUpdates() {
        startObservingEstimates()
        startPolling()
    }

    /// Realtime push: reload the visible location whenever a wait_estimates row
    /// changes. Started once — re-subscribing would orphan the channel.
    private func startObservingEstimates() {
        guard realtimeTask == nil else { return }
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.dataSource.estimateChanges() {
                try? await self.loadTiles(for: self.selectedLocationId)
            }
        }
    }

    /// Fallback poll so tiles stay live even if Realtime drops or is filtered.
    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { return }
                try? await self.loadTiles(for: self.selectedLocationId)
                await self.refreshLiveActivity()
            }
        }
    }

    private func loadTiles(for locationId: String) async throws {
        tilesByLocation[locationId] = try await dataSource.loadTiles(locationId: locationId)
    }

    /// Refresh the network-wide banner counters; leaves the current value on failure.
    private func refreshLiveActivity() async {
        if let a = try? await dataSource.liveActivity() { liveActivity = a }
    }

    /// Recent completed waits for a tile (real sparkline); [] if unavailable.
    func recentWaits(for routeStopId: String) async -> [Int] {
        (try? await dataSource.recentWaits(routeStopId: routeStopId)) ?? []
    }

    /// Tiles for any location (for the Stats picker, which is independent of Live).
    func statsTiles(locationId: String) async -> [RouteTile] {
        (try? await dataSource.loadTiles(locationId: locationId)) ?? SampleData.tiles(for: locationId)
    }

    /// Historical medians for the Stats screen; [:] if unavailable (UI falls back).
    func history(locationId: String, weekdayType: String) async -> [String: [Int: Int]] {
        (try? await dataSource.loadHistory(locationId: locationId, weekdayType: weekdayType)) ?? [:]
    }

    /// Fire-and-forget tile refresh for the current selection (used by setters).
    private func reloadSelectedTiles() {
        let id = selectedLocationId
        Task { [weak self] in
            guard let self else { return }
            do { try await self.loadTiles(for: id) }
            catch { self.loadError = error.localizedDescription }
        }
    }

    func openDetail(_ tile: RouteTile) { flow = .detail(tile) }

    func goBackToLive() {
        flow = nil
        tab = .live
    }

    // MARK: - Queue lifecycle (ported from startQueue/quickQueue/board/minimize/reset)

    /// Start queuing and open the full-screen tracker.
    func startQueue(_ tile: RouteTile) {
        active = tile
        elapsed = 0
        minimized = false
        queueOrigin = flow
        flow = .track
        startTimer()
        openSession(for: tile)
    }

    /// Start queuing but stay on Live with a minimized mini-pill.
    func quickQueue(_ tile: RouteTile) {
        active = tile
        elapsed = 0
        minimized = true
        queueOrigin = nil
        flow = nil
        tab = .live
        startTimer()
        openSession(for: tile)
    }

    /// Optimistically open a backend queue session (the local timer already runs).
    private func openSession(for tile: RouteTile) {
        sessionId = nil
        Task { [weak self] in
            guard let self else { return }
            do { self.sessionId = try await self.dataSource.startQueue(routeStopId: tile.id) }
            catch { self.loadError = error.localizedDescription }
        }
    }

    func expandQueue() {
        minimized = false
        flow = .track
    }

    /// Collapse the tracker back to a mini-pill, returning to the origin.
    func minimize() {
        minimized = true
        if case .detail = queueOrigin {
            flow = queueOrigin
        } else {
            flow = nil
            tab = .live
        }
    }

    /// Close the session on the backend (awards points, recomputes), then show
    /// the confirmation. Optimistic: we navigate immediately.
    func board() {
        flow = .done
        if let sid = sessionId {
            Task { [weak self] in
                try? await self?.dataSource.board(sessionId: sid)
            }
        }
    }

    func reset() {
        stopTimer()
        active = nil
        elapsed = 0
        minimized = false
        queueOrigin = nil
        sessionId = nil
        flow = nil
        tab = .live
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.active != nil else { return }
                self.elapsed += 1
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async {
        await authenticate { try await self.dataSource.signIn(email: email, password: password) }
    }

    func signUp(email: String, password: String) async {
        await authenticate { try await self.dataSource.signUp(email: email, password: password) }
    }

    private func authenticate(_ action: () async throws -> Void) async {
        authBusy = true
        authError = nil
        do {
            try await action()
            authBusy = false
            flow = nil
            tab = .live
            await load()                       // refresh data as the new user
        } catch {
            authBusy = false
            authError = error.localizedDescription
        }
    }

    func logOut() {
        Task { [weak self] in
            try? await self?.dataSource.signOut()
            self?.flow = .auth
        }
    }

    // MARK: - Formatting

    static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
