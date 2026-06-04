//
//  StatsView.swift
//  BusPulse
//
//  Stats tab — hourly wait chart, best crossing windows, all-day averages.
//  Reference: screenshot/stats.png and the `Stats` component in App.jsx.
//

import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    @State private var locId: String = ""
    @State private var dayOffset = 0
    @State private var statsTiles: [RouteTile] = []
    @State private var historyMap: [String: [Int: Int]] = [:]   // routeStopId → hour → median

    /// Chart-bar colour for an operator (AC7 reads as grey in the chart).
    private func chartColor(_ tile: RouteTile) -> Color {
        tile.badge == "AC7" ? Color(hex: "#AAAAAA") : tile.color
    }

    private var tiles: [RouteTile] { statsTiles }
    private var locName: String { model.allLocations.first { $0.id == locId }?.name ?? "" }

    /// Real historical median for this tile/hour, falling back to the synthetic
    /// model when history is absent (e.g. previews / mock data source).
    private func waitFor(_ tile: RouteTile, _ hour: Int) -> Int {
        historyMap[tile.id]?[hour]
            ?? Stats.wait(locationId: locId, dayOffset: dayOffset, opId: tile.id, hour: hour)
    }

    private func weekdayType(for offset: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        let wd = Calendar.current.component(.weekday, from: d)
        return (wd == 1 || wd == 7) ? "weekend" : "weekday"
    }

    var body: some View {
        // Title + location/day selectors stay pinned; only the cards scroll.
        ScrollView {
            VStack(spacing: 12) {
                hourlyChartCard
                bestWindowsCard
                allDayCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 12) {
                Text(Strings.t("statsTab", model.language))
                    .font(AppFont.body(15, weight: .bold))
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)

                selectors
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .background(theme.bg)
        }
        .background(theme.bg)
        .onAppear { if locId.isEmpty { locId = model.selectedLocationId } }
        .task(id: "\(locId)|\(dayOffset)") {
            guard !locId.isEmpty else { return }
            statsTiles = await model.statsTiles(locationId: locId)
            historyMap = await model.history(locationId: locId, weekdayType: weekdayType(for: dayOffset))
        }
    }

    // MARK: Selectors

    private var days: [(offset: Int, label: String)] {
        let dn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let mn = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let cal = Calendar.current
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: -i, to: Date())!
            let wd = dn[cal.component(.weekday, from: d) - 1]
            let mo = mn[cal.component(.month, from: d) - 1]
            let day = cal.component(.day, from: d)
            return (i, i == 0 ? "Today · \(wd) \(mo) \(day)" : "\(wd) · \(mo) \(day)")
        }
    }

    private var selectors: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(model.allLocations) { loc in
                    Button(loc.name) { locId = loc.id }
                }
            } label: { dropdownLabel(locName) }

            Menu {
                ForEach(days, id: \.offset) { d in
                    Button(d.label) { dayOffset = d.offset }
                }
            } label: { dropdownLabel(days[dayOffset].label) }
        }
    }

    private func dropdownLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(AppFont.body(13, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.card)
        .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .frame(maxWidth: .infinity)
    }

    // MARK: Hourly chart

    private var hourlyChartCard: some View {
        let cols = Stats.chartHours.map { hour -> (label: String, ops: [(tile: RouteTile, wait: Int)]) in
            (hour.label, tiles.map { ($0, waitFor($0, hour.hour)) })
        }
        let maxWait = max(cols.flatMap { $0.ops.map(\.wait) }.max() ?? 1, 1)

        let hr = Calendar.current.component(.hour, from: Date())
        let isPeak = (hr >= 7 && hr <= 9) || (hr >= 17 && hr <= 20)
        let peakLabel = isPeak ? "Peak now" : (hr >= 10 && hr <= 16 ? "Off-peak" : "Clearing")
        let peakColor = isPeak ? Palette.red : Palette.green

        return ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Hourly wait times").font(AppFont.body(14, weight: .bold)).foregroundStyle(theme.text)
                    Spacer()
                    Text(peakLabel)
                        .font(AppFont.body(11, weight: .bold)).foregroundStyle(peakColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(peakColor.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(peakColor.opacity(0.3), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                // Legend
                HStack(spacing: 14) {
                    ForEach(tiles) { t in
                        HStack(spacing: 5) {
                            Circle().fill(chartColor(t)).frame(width: 8, height: 8)
                            Text(t.badge).font(AppFont.body(11, weight: .semibold)).foregroundStyle(theme.muted)
                        }
                    }
                }
                // Bars
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(cols.enumerated()), id: \.offset) { _, col in
                        VStack(spacing: 6) {
                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(col.ops, id: \.tile.id) { entry in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(chartColor(entry.tile))
                                        .frame(width: 5, height: max(4, CGFloat(entry.wait) / CGFloat(maxWait) * 90))
                                }
                            }
                            Text(col.label).font(AppFont.body(9)).foregroundStyle(theme.faint)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 110, alignment: .bottom)
            }
        }
    }

    // MARK: Best crossing windows

    private var bestWindowsCard: some View {
        let avgs = Stats.chartHours.map { hour -> (label: String, avg: Int) in
            let waits = tiles.map { waitFor($0, hour.hour) }
            let avg = waits.isEmpty ? 99 : Int((Double(waits.reduce(0, +)) / Double(waits.count)).rounded())
            return (hour.label, avg)
        }.sorted { $0.avg < $1.avg }
        let best = Array(avgs.prefix(3))
        let maxAvg = max(avgs.last?.avg ?? 1, 1)

        let isWknd: Bool = {
            guard dayOffset > 0 else { return false }
            let d = Date().addingTimeInterval(-Double(dayOffset) * 86_400)
            let wd = Calendar.current.component(.weekday, from: d)
            return wd == 1 || wd == 7
        }()
        let note = isWknd ? "Weekend — 20–25% lighter than peak weekdays"
                          : "Weekday — expect 40% longer waits at peak hours"

        return ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Best crossing windows").font(AppFont.body(14, weight: .bold)).foregroundStyle(theme.text)
                    Spacer()
                    Text(locName).font(AppFont.body(11)).foregroundStyle(theme.muted)
                }
                ForEach(Array(best.enumerated()), id: \.offset) { i, w in
                    HStack(spacing: 10) {
                        Text(i == 0 ? "★" : "\(i + 1)")
                            .font(AppFont.body(13, weight: .bold))
                            .foregroundStyle(i == 0 ? Palette.gold : theme.faint)
                            .frame(width: 16)
                        Text(w.label).font(AppFont.body(13, weight: .bold)).foregroundStyle(theme.text).frame(width: 52, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(theme.line).frame(height: 6)
                                Capsule()
                                    .fill(i == 0 ? Palette.green : (i == 1 ? Palette.gold : theme.line))
                                    .frame(width: geo.size.width * CGFloat(max(12, 100 - Double(w.avg) / Double(maxAvg) * 80)) / 100, height: 6)
                            }
                        }
                        .frame(height: 6)
                        Text("~\(w.avg)m")
                            .font(AppFont.mono(13))
                            .foregroundStyle(i == 0 ? Palette.green : theme.muted)
                    }
                }
                Text(note)
                    .font(AppFont.body(11)).foregroundStyle(theme.faint)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: All-day averages

    private var allDayCard: some View {
        let opAvgs = tiles.map { t -> (tile: RouteTile, avg: Int) in
            let total = Stats.chartHours.reduce(0) { $0 + waitFor(t, $1.hour) }
            return (t, Int((Double(total) / Double(Stats.chartHours.count)).rounded()))
        }
        let maxAvg = max(opAvgs.map(\.avg).max() ?? 1, 1)

        return ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Avg wait · all day").font(AppFont.body(14, weight: .bold)).foregroundStyle(theme.text)
                    Spacer()
                    Text(dayOffset == 0 ? "Today" : days[dayOffset].label.components(separatedBy: " · ").first ?? "")
                        .font(AppFont.body(11)).foregroundStyle(theme.muted)
                }
                ForEach(opAvgs, id: \.tile.id) { entry in
                    HStack(spacing: 10) {
                        MiniBadge(badge: entry.tile.badge, colorHex: entry.tile.colorHex)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.tile.op).font(AppFont.body(12.5, weight: .semibold)).foregroundStyle(theme.text)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(theme.line).frame(height: 6)
                                    Capsule()
                                        .fill(entry.tile.badge == "AC7" ? Color(hex: "#888888") : entry.tile.color)
                                        .frame(width: geo.size.width * CGFloat(max(8, Double(entry.avg) / Double(maxAvg) * 100)) / 100, height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                        Text("\(entry.avg)m")
                            .font(AppFont.mono(15))
                            .foregroundStyle(entry.tile.crowd.color)
                    }
                }
            }
        }
    }
}

#Preview {
    StatsView()
        .environment(AppModel())
        .environment(\.theme, Theme.dark)
        .preferredColorScheme(.dark)
}
