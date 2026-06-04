//
//  SampleData.swift
//  BusPulse
//
//  Seed data ported verbatim from the prototype (LOCATIONS / TILES / RECENT_TRIPS).
//  A real API would replace this struct later.
//

import Foundation

enum SampleData {

    // MARK: Locations

    static let locations: [Location] = [
        Location(id: "woodlands_ckpt", name: "Woodlands Checkpoint",        side: .sg, direction: .sgToMy, note: "Departure bus bays"),
        Location(id: "kranji",         name: "Kranji MRT",                  side: .sg, direction: .sgToMy, note: "Bus berth A"),
        Location(id: "woodlands_ti",   name: "Woodlands Temp Interchange",  side: .sg, direction: .sgToMy, note: "Cross-border bays"),
        Location(id: "jbciq",          name: "JB Sentral CIQ",              side: .my, direction: .myToSg, note: "Level 1 boarding hall"),
        Location(id: "larkin",         name: "Larkin Terminal",             side: .my, direction: .myToSg, note: "Platform 2–4"),
    ]

    static func locations(for direction: Direction) -> [Location] {
        locations.filter { $0.direction == direction }
    }

    static func firstLocation(for direction: Direction) -> Location {
        locations(for: direction).first!
    }

    // MARK: Tiles per location

    static let tiles: [String: [RouteTile]] = [
        "woodlands_ckpt": [
            RouteTile(id: "ac7", badge: "AC7", lines: ["AC7"], colorHex: "#1F9E6B", op: "Causeway Express", to: "JB Sentral",     low: 5,  high: 9,  crowd: .low,  next: 3,  reports: 6,  fresh: 3),
            RouteTile(id: "cw",  badge: "CW",  lines: ["CW"],  colorHex: "#F2C200", op: "Causeway Link",    to: "JB Sentral",     low: 6,  high: 10, crowd: .low,  next: 4,  reports: 13, fresh: 2),
            RouteTile(id: "sbs", badge: "SBS", lines: ["160", "170X", "170", "950"], colorHex: "#7C5CFF", op: "SBS · SMRT", to: "JB / Larkin", low: 14, high: 21, crowd: .med, next: 7, reports: 18, fresh: 1),
        ],
        "kranji": [
            RouteTile(id: "cw",  badge: "CW",  lines: ["CW"],  colorHex: "#F2C200", op: "Causeway Link", to: "JB Sentral",          low: 7, high: 12, crowd: .low, next: 5, reports: 9, fresh: 2),
            RouteTile(id: "sbs", badge: "SBS", lines: ["160", "170X"], colorHex: "#7C5CFF", op: "SBS Transit", to: "JB Sentral / Larkin", low: 9, high: 16, crowd: .med, next: 6, reports: 9, fresh: 3),
        ],
        "woodlands_ti": [
            RouteTile(id: "950", badge: "950", lines: ["950"], colorHex: "#E23B3B", op: "SMRT", to: "JB Sentral", low: 18, high: 25, crowd: .high, next: 7, reports: 16, fresh: 2),
        ],
        "jbciq": [
            RouteTile(id: "ac7", badge: "AC7", lines: ["AC7"], colorHex: "#1F9E6B", op: "Causeway Express", to: "Newton",            low: 8,  high: 13, crowd: .low,  next: 4,  reports: 7,  fresh: 3),
            RouteTile(id: "cw",  badge: "CW",  lines: ["CW"],  colorHex: "#F2C200", op: "Causeway Link",    to: "Singapore",         low: 18, high: 26, crowd: .high, next: 6,  reports: 24, fresh: 1),
            RouteTile(id: "sbs", badge: "SBS", lines: ["160", "170X", "170"], colorHex: "#7C5CFF", op: "SBS Transit", to: "Queen St / Kranji", low: 22, high: 30, crowd: .high, next: 9, reports: 17, fresh: 2),
            RouteTile(id: "950", badge: "950", lines: ["950"], colorHex: "#E23B3B", op: "SMRT", to: "Woodlands", low: 24, high: 33, crowd: .high, next: 11, reports: 19, fresh: 4),
        ],
        "larkin": [
            RouteTile(id: "cw",  badge: "CW",  lines: ["CW"],  colorHex: "#F2C200", op: "Causeway Link", to: "Queen St", low: 11, high: 17, crowd: .med,  next: 5, reports: 6,  fresh: 5),
            RouteTile(id: "sbs", badge: "SBS", lines: ["170"], colorHex: "#7C5CFF", op: "SBS Transit",   to: "Queen St", low: 15, high: 23, crowd: .high, next: 9, reports: 10, fresh: 4),
        ],
    ]

    /// Tiles for a location, sorted by lower-bound wait (matches prototype's `.sort`).
    static func tiles(for locationId: String) -> [RouteTile] {
        (tiles[locationId] ?? []).sorted { $0.low < $1.low }
    }

    /// Every tile across all locations (for network-wide counters).
    static var allTiles: [RouteTile] { tiles.values.flatMap { $0 } }

    static func totalReports(for locationId: String) -> Int {
        (tiles[locationId] ?? []).reduce(0) { $0 + $1.reports }
    }

    // MARK: Recent trips

    static let recentTrips: [RecentTrip] = [
        RecentTrip(badge: "CW",  colorHex: "#F2C200", op: "Causeway Link",    to: "JB Sentral", wait: "23m", when: "Today · 8:14am"),
        RecentTrip(badge: "SBS", colorHex: "#7C5CFF", op: "SBS Transit",      to: "Queen St",   wait: "18m", when: "Yesterday · 7:22pm"),
        RecentTrip(badge: "AC7", colorHex: "#1F9E6B", op: "Causeway Express", to: "Newton",     wait: "12m", when: "Mon · 5:45pm"),
        RecentTrip(badge: "950", colorHex: "#E23B3B", op: "SMRT",             to: "Woodlands",  wait: "31m", when: "Mon · 8:55am"),
    ]

    static let rewardPoints = 1240
}

// MARK: - Stats synthesis (ported from `genWait`)

enum Stats {
    /// Hours shown on the Stats bar chart.
    static let chartHours: [(label: String, hour: Int)] = [
        ("6am", 6), ("8am", 8), ("10am", 10), ("12pm", 12),
        ("2pm", 14), ("4pm", 16), ("6pm", 18), ("8pm", 20), ("10pm", 22),
    ]

    /// Deterministic synthetic wait for a location/day/operator/hour — mirrors `genWait()`.
    static func wait(locationId: String, dayOffset: Int, opId: String, hour: Int) -> Int {
        guard let tile = (SampleData.tiles[locationId] ?? []).first(where: { $0.id == opId }) else { return 0 }
        let base = Double(tile.low + tile.high) / 2
        let isPeak = (hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 20)
        let pastDay = Date().addingTimeInterval(-Double(dayOffset) * 86_400)
        let weekday = Calendar.current.component(.weekday, from: pastDay) // 1 = Sun, 7 = Sat
        let isWeekend = dayOffset > 0 && (weekday == 1 || weekday == 7)

        let locCode = Int(locationId.unicodeScalars.first!.value)
        let opCode = Int(opId.unicodeScalars.first!.value)
        let noise = ((locCode * 13 + dayOffset * 7 + opCode * 11 + hour * 5) % 12) - 6

        let factor = isPeak ? 1.55 : (isWeekend ? 0.75 : 0.9)
        return max(3, Int((base * factor + Double(noise)).rounded()))
    }
}
