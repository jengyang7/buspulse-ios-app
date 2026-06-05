//
//  RouteDetailView.swift
//  BusPulse
//
//  Route details — hero estimate, "how this estimate is made", sparkline.
//  Reference: screenshot/route.png and the `view === "detail"` block in App.jsx.
//

import SwiftUI

struct RouteDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    private let initial: RouteTile
    @State private var barsGrown = false
    @State private var realSpark: [Int] = []
    @State private var arrivals: [BusArrival]?    // nil = loading; [] = none
    @State private var arrivalsUpdatedAt: Date?
    @State private var refreshing = false

    init(tile: RouteTile) { self.initial = tile }

    /// Live tile: track the current value from the model so the detail screen
    /// updates as estimates change, falling back to the tapped snapshot.
    private var tile: RouteTile {
        model.tiles.first { $0.id == initial.id } ?? initial
    }

    /// Whether there are enough real reports to plot a meaningful trend. With one
    /// or two we'd just draw a lone block, so we fall back to the typical pattern.
    private var hasRealSpark: Bool { realSpark.count >= 3 }
    /// Real recent boarded waits when there are enough, else the synthetic sparkline.
    private var spark: [Int] { hasRealSpark ? realSpark : Estimate.spark(tile) }

    // MARK: Reconcile the crowd estimate with live arrivals
    // You can't board before the first bus arrives, so the wait can't be shorter
    // than the soonest *boardable* bus (prefer one that isn't packed). The high
    // end is left open — Causeway traffic and clearance can stretch it.

    /// Soonest boardable bus across all live services (minutes), if any.
    private var soonestArrival: Int? {
        guard let arrivals, !arrivals.isEmpty else { return nil }
        let etas = arrivals.flatMap(\.etas)
        let notPacked = etas.filter { $0.load != .high }.compactMap(\.minutes)
        return notPacked.min() ?? etas.compactMap(\.minutes).min()
    }
    /// Estimate floored by the soonest arrival; low/high follow it.
    private var estAdj: Int { max(tile.estimate, soonestArrival ?? 0) }
    private var lowAdj: Int { tile.flooredRange(soonestArrival: soonestArrival).low }
    private var highAdj: Int { tile.flooredRange(soonestArrival: soonestArrival).high }
    /// True when live arrivals pushed the estimate up (the otherwise-impossible case).
    private var arrivalFloored: Bool { (soonestArrival ?? 0) > tile.estimate }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView {
                VStack(spacing: 14) {
                    hero
                    if tile.showsRoutes { routesCard }
                    arrivalsCard
                    sourceCard
                    sparkCard
                    boardButton
                    notifyButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(theme.bg)
        .task(id: tile.id) { realSpark = await model.recentWaits(for: tile.id) }
        .task(id: tile.id) {
            // Live arrivals fetch immediately, then refresh once per minute (a
            // couple seconds past :00) while the screen is open. Skipped for
            // cross-border / unmapped tiles (static note).
            guard !tile.crossBorder, tile.ltaStopCode != nil else { return }
            while !Task.isCancelled {
                arrivals = await model.arrivals(for: tile)
                arrivalsUpdatedAt = Date()
                try? await Task.sleep(for: .seconds(AppModel.secondsToNextTick()))
            }
        }
    }

    // MARK: Live arrivals (LTA DataMall)

    /// Whether live arrivals can actually be fetched for this tile.
    private var hasLiveArrivals: Bool { !tile.crossBorder && tile.ltaStopCode != nil }

    private var arrivalsCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Live bus arrivals")
                        .font(AppFont.body(13, weight: .bold))
                        .foregroundStyle(theme.text)
                    Spacer()
                    // Only LTA-served tiles get the source / freshness label; for
                    // cross-border or unmapped tiles there's no live feed to credit.
                    if hasLiveArrivals {
                        if let updatedAt = arrivalsUpdatedAt {
                            let secs = max(0, Int(Date().timeIntervalSince(updatedAt)))
                            Text("updated \(secs < 60 ? "\(secs)s" : "\(secs / 60)m") ago")
                                .font(AppFont.body(10.5))
                                .foregroundStyle(theme.faint)
                        } else {
                            Text("LTA DataMall")
                                .font(AppFont.body(10.5))
                                .foregroundStyle(theme.faint)
                        }
                        refreshButton
                    }
                }
                arrivalsBody
            }
        }
    }

    private var refreshButton: some View {
        Button { refreshArrivals() } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(refreshing ? theme.faint : Palette.blue)
                .rotationEffect(.degrees(refreshing ? 360 : 0))
                .animation(refreshing
                    ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                    : .default, value: refreshing)
                .frame(width: 28, height: 28)
                .background(theme.card2)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(refreshing)
    }

    private func refreshArrivals() {
        guard hasLiveArrivals, !refreshing else { return }
        refreshing = true
        Task {
            arrivals = await model.arrivals(for: tile)
            arrivalsUpdatedAt = Date()
            refreshing = false
        }
    }

    @ViewBuilder private var arrivalsBody: some View {
        if tile.crossBorder {
            arrivalsNote("Live arrivals not available for this bus operator.")
        } else if tile.ltaStopCode == nil {
            arrivalsNote("Live arrivals not configured for this stop yet.")
        } else if let arrivals {
            if arrivals.isEmpty {
                arrivalsNote("No buses arriving right now.")
            } else {
                VStack(spacing: 8) {
                    ForEach(arrivals) { arrivalRow($0) }
                }
            }
        } else {
            arrivalsNote("Loading live arrivals…")
        }
    }

    private func arrivalRow(_ a: BusArrival) -> some View {
        HStack(spacing: 10) {
            Text(a.service)
                .font(AppFont.display(14))
                .foregroundStyle(theme.text)
                .frame(minWidth: 44, alignment: .leading)
            Spacer()
            ForEach(a.etas) { eta in
                Text(eta.label)
                    .font(AppFont.mono(13))
                    .foregroundStyle(eta.minutes == nil ? theme.faint : eta.load.color)
                    .frame(minWidth: 40)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func arrivalsNote(_ text: String) -> some View {
        Text(text)
            .font(AppFont.body(12))
            .foregroundStyle(theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    // MARK: Nav bar

    private var navBar: some View {
        HStack {
            GlassIconButton(system: "arrow.left") { model.goBackToLive() }
            Spacer()
            Text(Strings.t("routeDetails", model.language))
                .font(AppFont.body(15, weight: .bold))
                .foregroundStyle(theme.text)
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Hero

    private var hero: some View {
        ThemedCard(padding: 22) {
            VStack(spacing: 10) {
                OperatorBadge(tile: tile, large: true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(lowAdj)–\(highAdj)")
                        .font(AppFont.mono(46))
                        .foregroundStyle(tile.crowd.color)
                    Text("min")
                        .font(AppFont.body(16))
                        .foregroundStyle(theme.muted)
                }
                Text("\(tile.op) · to \(tile.to)")
                    .font(AppFont.body(13))
                    .foregroundStyle(theme.muted)
                HStack(spacing: 8) {
                    CrowdIndicator(level: tile.crowd,
                                   label: Strings.t(tile.crowd.labelKey, model.language))
                    if let next = soonestArrival {
                        Text("·").foregroundStyle(theme.faint)
                        Text("🕒 \(Strings.t("nextBus", model.language)) \(next)m")
                            .font(AppFont.body(12))
                            .foregroundStyle(theme.muted)
                    }
                }
                if arrivalFloored, let next = soonestArrival {
                    Text("Matched to the next bus — you can't board before it arrives (\(next)m)")
                        .font(AppFont.body(10.5))
                        .foregroundStyle(Palette.blue)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Routes card

    private var routesCard: some View {
        ThemedCard {
            HStack {
                Text(Strings.t("routes", model.language))
                    .font(AppFont.body(12, weight: .semibold))
                    .foregroundStyle(theme.muted)
                Spacer()
                LineChips(tile: tile)
            }
        }
    }

    // MARK: Source card

    private var sourceCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("How this estimate is made")
                        .font(AppFont.body(13, weight: .bold))
                        .foregroundStyle(theme.text)
                    Spacer()
                    confidenceBadge
                }
                HStack(spacing: 10) {
                    statCell("\(tile.reports)", "recent reports")
                    statCell("\(tile.activeCount)", "timing now")
                    statCell("\(tile.estimate)m", "estimate")
                }
            }
        }
    }

    /// Green "X confidence" for live estimates; a calmer blue "Typical for this
    /// time" when the estimate is driven only by the historical baseline.
    private var confidenceBadge: some View {
        let color = tile.isTypical ? Palette.blue : Palette.green
        let text = tile.isTypical ? "Typical for this time" : "\(tile.confidence) confidence"
        return Text(text)
            .font(AppFont.body(11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(AppFont.body(17, weight: .bold)).foregroundStyle(theme.text)
            Text(label).font(AppFont.body(10.5)).foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Sparkline

    private var sparkCard: some View {
        let maxV = max(spark.max() ?? 1, 1)
        return ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(hasRealSpark ? "Recent reported waits" : "Typical wait pattern")
                        .font(AppFont.body(13, weight: .bold))
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text(hasRealSpark ? "last 30 min · newest →" : "usual for this time")
                        .font(AppFont.body(11))
                        .foregroundStyle(theme.muted)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(spark.enumerated()), id: \.offset) { i, v in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i == spark.count - 1 ? tile.crowd.color : theme.line)
                            // Cap width so few bars render as a left-aligned mini-chart
                            // rather than one stretched block; floor height so short
                            // waits stay visible.
                            .frame(maxWidth: 38)
                            .frame(height: max(8, CGFloat(v) / CGFloat(maxV) * 70))
                            .scaleEffect(y: barsGrown ? 1 : 0, anchor: .bottom)
                            .animation(.easeOut(duration: 0.4).delay(Double(i) * 0.045), value: barsGrown)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 70, alignment: .bottom)
                .onAppear { barsGrown = true }
            }
        }
    }

    // MARK: Buttons

    private var boardButton: some View {
        let queuing = model.active != nil
        return Button {
            if !queuing { model.startQueue(tile) }
        } label: {
            Text(queuing ? "Queuing \(model.active!.badge) now" : Strings.t("startQueue", model.language))
                .font(AppFont.body(15, weight: .bold))
                .foregroundStyle(Color(hex: "#1A1A1A"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Palette.lime.opacity(queuing ? 0.5 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(queuing)
    }

    private var notifyButton: some View {
        Button {} label: {
            Text("🔔 Notify me when queue drops below 10m")
                .font(AppFont.body(13, weight: .semibold))
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(theme.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RouteDetailView(tile: SampleData.tiles(for: "jbciq")[3])
        .environment(AppModel())
        .environment(\.theme, Theme.dark)
        .preferredColorScheme(.dark)
}
