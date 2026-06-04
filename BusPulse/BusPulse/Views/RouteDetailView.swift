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

    init(tile: RouteTile) { self.initial = tile }

    /// Live tile: track the current value from the model so the detail screen
    /// updates as estimates change, falling back to the tapped snapshot.
    private var tile: RouteTile {
        model.tiles.first { $0.id == initial.id } ?? initial
    }

    /// Real recent boarded waits when available, else the synthetic sparkline.
    private var spark: [Int] { realSpark.isEmpty ? Estimate.spark(tile) : realSpark }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView {
                VStack(spacing: 14) {
                    hero
                    if tile.showsRoutes { routesCard }
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
                    Text("\(tile.low)–\(tile.high)")
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
                    Text("·").foregroundStyle(theme.faint)
                    Text("🕒 \(Strings.t("nextBus", model.language)) \(tile.next)m")
                        .font(AppFont.body(12))
                        .foregroundStyle(theme.muted)
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
                    Text(realSpark.isEmpty ? "Typical wait pattern" : "Recent reported waits")
                        .font(AppFont.body(13, weight: .bold))
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text(realSpark.isEmpty ? "usual for this time" : "last 30 min · newest →")
                        .font(AppFont.body(11))
                        .foregroundStyle(theme.muted)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(spark.enumerated()), id: \.offset) { i, v in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i == spark.count - 1 ? tile.crowd.color : theme.line)
                            .frame(maxWidth: .infinity)
                            .frame(height: CGFloat(v) / CGFloat(maxV) * 70)
                            .scaleEffect(y: barsGrown ? 1 : 0, anchor: .bottom)
                            .animation(.easeOut(duration: 0.4).delay(Double(i) * 0.045), value: barsGrown)
                    }
                }
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
