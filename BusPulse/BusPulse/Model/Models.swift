//
//  Models.swift
//  BusPulse
//
//  Domain types ported from the prototype's LOCATIONS / TILES.
//

import SwiftUI

// MARK: - Direction & Side

enum Direction: String, CaseIterable, Identifiable {
    case sgToMy = "SG-MY"
    case myToSg = "MY-SG"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sgToMy: "🇸🇬 SG → MY 🇲🇾"
        case .myToSg: "🇲🇾 MY → SG 🇸🇬"
        }
    }
}

enum Side: String {
    case sg = "SG"
    case my = "MY"
}

// MARK: - Crowd level

enum CrowdLevel: String {
    case low, med, high

    var color: Color {
        switch self {
        case .low:  Palette.green
        case .med:  Palette.orange
        case .high: Palette.red
        }
    }

    /// Number of filled bars in the crowd indicator (1–3).
    var bars: Int {
        switch self {
        case .low: 1
        case .med: 2
        case .high: 3
        }
    }

    /// Localization key suffix; full key is "crowd_low" / "crowd_med" / "crowd_high".
    var labelKey: String { "crowd_\(rawValue)" }
}

// MARK: - Location

struct Location: Identifiable, Hashable {
    let id: String
    let name: String
    let side: Side
    let direction: Direction
    let note: String
}

// MARK: - Route tile

struct RouteTile: Identifiable, Hashable {
    let id: String
    let badge: String
    let lines: [String]
    /// Operator colour as a hex string so we can decide text contrast (AC7/CW).
    let colorHex: String
    let op: String
    let to: String
    let low: Int
    let high: Int
    let crowd: CrowdLevel
    let next: Int
    let reports: Int
    /// Seconds since this estimate was last refreshed (drives the "updated …" label).
    let fresh: Int

    // Server-computed fields (§2). Default to the prototype's derived math so
    // SampleData / previews don't need to supply them.
    let estimate: Int       // central estimate (max of weighted median, censored floor)
    let confidence: String  // "High" | "Good" | "Building"
    let activeCount: Int    // people currently queuing this tile ("timing now")

    init(id: String, badge: String, lines: [String], colorHex: String, op: String,
         to: String, low: Int, high: Int, crowd: CrowdLevel, next: Int,
         reports: Int, fresh: Int,
         estimate: Int? = nil, confidence: String? = nil, activeCount: Int? = nil) {
        self.id = id; self.badge = badge; self.lines = lines; self.colorHex = colorHex
        self.op = op; self.to = to; self.low = low; self.high = high; self.crowd = crowd
        self.next = next; self.reports = reports; self.fresh = fresh
        self.estimate = estimate ?? Int((Double(low + high) / 2).rounded())
        self.confidence = confidence ?? (reports >= 12 ? "High" : reports >= 7 ? "Good" : "Building")
        self.activeCount = activeCount ?? max(1, min(4, Int((Double(reports) / 6).rounded())))
    }

    var color: Color { Color(hex: colorHex) }

    /// Human "updated X ago" — seconds under a minute, then minutes, then hours.
    var freshLabel: String {
        let s = max(fresh, 0)
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        return m < 60 ? "\(m)m ago" : "\(m / 60)h ago"
    }

    /// AC7 renders as a white badge with dark text; CW/lime use dark text too.
    var badgeBackground: Color { badge == "AC7" ? .white : color }
    var badgeForeground: Color {
        if badge == "AC7" { return Color(hex: "#1A1A1A") }
        return OperatorColor.wantsDarkText(on: colorHex) ? Color(hex: "#1A1A1A") : .white
    }

    /// The tile bundles multiple route numbers (e.g. SBS family) — show the chip list.
    var showsRoutes: Bool { lines.count > 1 || lines.first != badge }
}

// MARK: - Recent trip (profile)

struct RecentTrip: Identifiable {
    let id = UUID()
    let badge: String
    let colorHex: String
    let op: String
    let to: String
    let wait: String
    let when: String

    var color: Color { Color(hex: colorHex) }
}

// MARK: - Derived estimate helpers (ported from prototype)

enum Estimate {
    /// Sparkline of recent reported waits — deterministic, mirrors `spark()`.
    static func spark(_ t: RouteTile) -> [Int] {
        let span = max(t.high - t.low, 1)
        return (0..<9).map { i in t.low + ((i * 31 + t.high * 17) % (span + 1)) }
    }

    /// How many riders are timing this route right now — mirrors `liveRecorders()`.
    static func liveRecorders(_ t: RouteTile) -> Int {
        max(1, min(4, Int((Double(t.reports) / 6).rounded())))
    }

    /// Confidence label — mirrors `confidence()`.
    static func confidence(_ t: RouteTile) -> String {
        if t.reports >= 12 { return "High" }
        if t.reports >= 7 { return "Good" }
        return "Building"
    }

    /// Latest boarded wait — mirrors `latestBoarded()`.
    static func latestBoarded(_ t: RouteTile) -> Int {
        Int((Double(t.low + t.high) / 2).rounded())
    }
}
