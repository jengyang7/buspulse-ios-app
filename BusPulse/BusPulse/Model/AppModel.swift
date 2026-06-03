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
        didSet { selectedLocationId = SampleData.firstLocation(for: direction).id }
    }
    var selectedLocationId: String = SampleData.firstLocation(for: .sgToMy).id

    // Active queue
    private(set) var active: RouteTile?
    private(set) var elapsed: Int = 0        // seconds
    var minimized = false
    private var queueOrigin: Flow?           // where the queue was started from
    private var timerTask: Task<Void, Never>?

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

    // MARK: - Derived

    var selectedLocation: Location {
        SampleData.locations.first { $0.id == selectedLocationId }!
    }
    var tiles: [RouteTile] { SampleData.tiles(for: selectedLocationId) }
    var totalReports: Int { SampleData.totalReports(for: selectedLocationId) }

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

    func selectLocation(_ id: String) { selectedLocationId = id }

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

    func board() { flow = .done }

    func reset() {
        stopTimer()
        active = nil
        elapsed = 0
        minimized = false
        queueOrigin = nil
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

    func logOut() { flow = .auth }
    func signIn() {
        flow = nil
        tab = .live
    }

    // MARK: - Formatting

    static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
