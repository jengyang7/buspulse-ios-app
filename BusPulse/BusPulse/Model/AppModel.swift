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
            restartLtaPolling()
        }
    }
    var selectedLocationId: String = SampleData.firstLocation(for: .sgToMy).id

    // Active queue
    private(set) var active: RouteTile?
    private(set) var elapsed: Int = 0        // seconds
    var minimized = false
    private var queueOrigin: Flow?           // where the queue was started from
    private var timerTask: Task<Void, Never>?
    /// Wall-clock start of the active queue. Elapsed is derived from this so the
    /// timer stays accurate across app backgrounding (when the tick loop freezes).
    private var queueStartedAt: Date?
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

    // Profile — seeded from SampleData for previews/offline, replaced by loadProfile().
    var profileName = "Jayden Kong"
    var profileEmail = "jayden@buspulse.app"
    var rewardPoints = SampleData.rewardPoints
    var tripsLogged = 42
    var reportsShared = 318
    var avgWaitMin = 17
    var recentTrips: [RecentTrip] = SampleData.recentTrips

    var theme: Theme { appearance.theme }
    var colorScheme: ColorScheme { appearance == .dark ? .dark : .light }

    // MARK: - Data source

    private let dataSource: DataSource

    // LTA next-bus cache — populated by the background poller on the home screen
    // for every LTA-served (non-cross-border) tile. Keyed by tile.id.
    private(set) var ltaNextBus: [String: Int] = [:]
    private(set) var ltaFetchedAt: [String: Date] = [:]
    /// Bumped after each LTA refresh so views observing it re-render even when a
    /// dictionary mutation alone wouldn't invalidate them.
    private(set) var ltaTick = 0
    private var ltaTask: Task<Void, Never>?
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
        restartLtaPolling()
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
            await loadProfile()
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
        startLtaPolling()
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
    /// Fires once per minute (a couple seconds past :00) in step with the other refreshes.
    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.secondsToNextTick()))
                guard let self else { return }
                try? await self.loadTiles(for: self.selectedLocationId)
                await self.refreshLiveActivity()
            }
        }
    }

    /// Polls LTA arrivals for the visible tiles once per minute (a couple seconds
    /// past :00). Idempotent — only one loop runs at a time.
    private func startLtaPolling() {
        guard ltaTask == nil else { return }
        ltaTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshLtaForVisibleTiles()
                try? await Task.sleep(for: .seconds(Self.secondsToNextTick()))
            }
        }
    }

    /// Seconds to sleep until the next refresh tick — the next sharp minute plus a
    /// short settle delay so LTA DataMall has published the new minute's data and
    /// clients don't all hit the API at exactly :00. Polls land around :02.
    static func secondsToNextTick() -> Int {
        let s = Calendar.current.component(.second, from: Date())
        let settle = 2
        return (60 - s) + settle
    }

    /// Fetch LTA next-bus times for the visible tiles right now (used on app open
    /// and tab return so the home screen doesn't wait for the next tick).
    func refreshNextBus() async {
        await refreshLtaForVisibleTiles()
    }

    /// Cancel the running LTA loop, clear stale cache, and start fresh.
    /// Call this when the selected location or direction changes.
    private func restartLtaPolling() {
        ltaTask?.cancel()
        ltaTask = nil
        ltaNextBus = [:]
        ltaFetchedAt = [:]
        startLtaPolling()
    }

    /// Fetch LTA arrivals for every LTA-served tile (SBS, 950, etc. — anything
    /// that isn't cross-border and has an ltaStopCode), updating ltaNextBus with
    /// the soonest non-packed arrival (or any, if all are packed).
    private func refreshLtaForVisibleTiles() async {
        let ltaTiles = tiles.filter { !$0.crossBorder && $0.ltaStopCode != nil }
        let now = Date()
        for tile in ltaTiles {
            let results = await arrivals(for: tile)
            let etas = results.flatMap(\.etas)
            let soonest = etas.filter { $0.load != .high }.compactMap(\.minutes).min()
                       ?? etas.compactMap(\.minutes).min()
            // Always stamp fetchedAt (marks the tile as "checked", so the UI can
            // drop the "checking…" placeholder); only set a value when a bus exists.
            ltaFetchedAt[tile.id] = now
            if let m = soonest { ltaNextBus[tile.id] = m }
        }
        ltaTick &+= 1                       // nudge observers to re-render
    }

    private func loadTiles(for locationId: String) async throws {
        tilesByLocation[locationId] = try await dataSource.loadTiles(locationId: locationId)
    }

    /// Refresh the network-wide banner counters; leaves the current value on failure.
    private func refreshLiveActivity() async {
        if let a = try? await dataSource.liveActivity() { liveActivity = a }
    }

    /// Load the signed-in user's profile + recent trips for the account screen.
    /// Leaves the seeded values in place on failure (e.g. offline / signed out).
    func loadProfile() async {
        if let p = try? await dataSource.loadProfileSummary() {
            profileName = p.name
            profileEmail = p.email
            rewardPoints = p.rewardPoints
            tripsLogged = p.tripsLogged
            reportsShared = p.reportsShared
            avgWaitMin = p.avgWaitMin
        }
        if let trips = try? await dataSource.recentTrips() {
            recentTrips = trips
        }
    }

    /// Recent completed waits for a tile (real sparkline); [] if unavailable.
    func recentWaits(for routeStopId: String) async -> [Int] {
        (try? await dataSource.recentWaits(routeStopId: routeStopId)) ?? []
    }

    /// Live LTA arrivals for a tile's services; [] for cross-border/unmapped/error.
    func arrivals(for tile: RouteTile) async -> [BusArrival] {
        guard !tile.crossBorder, let code = tile.ltaStopCode else { return [] }
        return (try? await dataSource.busArrivals(stopCode: code, services: tile.lines)) ?? []
    }

    /// Tiles for any location (for the Stats picker, which is independent of Live).
    func statsTiles(locationId: String) async -> [RouteTile] {
        (try? await dataSource.loadTiles(locationId: locationId)) ?? SampleData.tiles(for: locationId)
    }

    /// Historical medians for the Stats screen; [:] if unavailable (UI falls back).
    func history(locationId: String, weekdayType: String) async -> [String: [Int: Int]] {
        (try? await dataSource.loadHistory(locationId: locationId, weekdayType: weekdayType)) ?? [:]
    }

    /// Per-route, per-hour median wait (min) for a location on one day, keyed
    /// [routeStopId: [hour: median]]; [:] if unavailable.
    func routeWaitByHour(locationId: String, date: Date) async -> [String: [Int: Int]] {
        (try? await dataSource.routeWaitByHour(locationId: locationId, date: date)) ?? [:]
    }

    /// Fire-and-forget tile refresh for the current selection (used by setters).
    private func reloadSelectedTiles() {
        let id = selectedLocationId
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.loadTiles(for: id)
                // Tiles for the new selection are in now — fetch their next-bus
                // times immediately instead of waiting for the next minute tick.
                if self.selectedLocationId == id { await self.refreshNextBus() }
            }
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
                // Points + trip counts changed — refresh the profile stats.
                await self?.loadProfile()
            }
        }
    }

    func reset() {
        stopTimer()
        active = nil
        elapsed = 0
        queueStartedAt = nil
        minimized = false
        queueOrigin = nil
        sessionId = nil
        flow = nil
        tab = .live
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        queueStartedAt = Date()
        elapsed = 0
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.active != nil else { return }
                self.syncElapsed()
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Recompute elapsed from the wall-clock start. Called every tick and on
    /// foreground return, so time backgrounded is counted correctly.
    func syncElapsed() {
        guard active != nil, let start = queueStartedAt else { return }
        elapsed = max(0, Int(Date().timeIntervalSince(start)))
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
