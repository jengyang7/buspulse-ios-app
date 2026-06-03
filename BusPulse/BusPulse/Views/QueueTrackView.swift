//
//  QueueTrackView.swift
//  BusPulse
//
//  Active queue tracker — circular progress ring + live mm:ss timer.
//  Reference: screenshot/queue.png and the `view === "track"` block in App.jsx.
//

import SwiftUI

struct QueueTrackView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        guard let active = model.active else { return AnyView(EmptyView()) }
        return AnyView(content(active))
    }

    private func content(_ active: RouteTile) -> some View {
        VStack(spacing: 0) {
            // Drag handle / minimize
            Capsule()
                .fill(theme.faint.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .onTapGesture { model.minimize() }

            header

            ring(active)
                .padding(.vertical, 24)

            queuerCard(active)
            censoredCard(active)
                .padding(.top, 12)

            Spacer()

            boardButton
            leaveButton
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .background(theme.bg)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Follow the finger downward only.
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        model.minimize()
                        dragOffset = 0
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    private var header: some View {
        HStack {
            LiveDot(size: 10)
                .frame(width: 34, alignment: .leading)
            Spacer()
            Text(Strings.t("queuingNow", model.language))
                .font(AppFont.body(15, weight: .bold))
                .foregroundStyle(theme.text)
            Spacer()
            GlassIconButton(system: "chevron.down") { model.minimize() }
        }
    }

    // MARK: Ring (TimelineView drives the live mm:ss)

    private func ring(_ active: RouteTile) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ZStack {
                Circle()
                    .stroke(theme.line, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: model.progress)
                    .stroke(model.isOvertime ? Palette.red : Palette.gold,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: model.progress)

                VStack(spacing: 6) {
                    Text(AppModel.clock(model.elapsed))
                        .font(AppFont.mono(48))
                        .foregroundStyle(theme.text)
                    Text("\(Strings.t("yourWaitEst", model.language)) \(active.low)–\(active.high)m")
                        .font(AppFont.body(12))
                        .foregroundStyle(theme.muted)
                }
            }
            .frame(width: 220, height: 220)
        }
    }

    // MARK: Cards

    private func queuerCard(_ active: RouteTile) -> some View {
        ThemedCard {
            HStack(spacing: 14) {
                OperatorBadge(tile: active, large: true)
                VStack(alignment: .leading, spacing: 4) {
                    if active.showsRoutes {
                        LineChips(tile: active, small: true)
                    } else {
                        Text(active.op)
                            .font(AppFont.body(15, weight: .bold))
                            .foregroundStyle(theme.text)
                    }
                    Text("to \(active.to)")
                        .font(AppFont.body(13))
                        .foregroundStyle(theme.muted)
                }
                Spacer()
            }
        }
    }

    private func censoredCard(_ active: RouteTile) -> some View {
        HStack(spacing: 12) {
            LiveDot(size: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your timer is live for \(active.badge)")
                    .font(AppFont.body(13, weight: .bold))
                    .foregroundStyle(theme.text)
                Text("Others see \u{201C}≥ \(model.elapsed / 60)m and still waiting\u{201D} — boarding will add your final wait to the shared estimate.")
                    .font(AppFont.body(11.5))
                    .foregroundStyle(theme.muted)
            }
        }
        .padding(14)
        .background(Palette.green.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.green.opacity(0.24), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    // MARK: Buttons

    private var boardButton: some View {
        Button { model.board() } label: {
            Text("\(Strings.t("boarded", model.language)) ✓")
                .font(AppFont.body(15, weight: .bold))
                .foregroundStyle(Color(hex: "#1A1A1A"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Palette.lime)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var leaveButton: some View {
        Button { model.reset() } label: {
            Text(Strings.t("leftQueue", model.language))
                .font(AppFont.body(14, weight: .semibold))
                .foregroundStyle(Palette.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Palette.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mini-pill (minimized queue)

struct MiniPill: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        guard let active = model.active else { return AnyView(EmptyView()) }
        // Rendered inside `tabViewBottomAccessory`, so the system supplies the
        // Liquid Glass background and morphs it with the tab bar — no card fill
        // of our own. Compact single-row layout to fit the accessory height.
        return AnyView(
            Button { model.expandQueue() } label: {
                HStack(spacing: 10) {
                    MiniBadge(badge: active.badge, colorHex: active.colorHex, side: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Queuing now · \(active.op)")
                            .font(AppFont.body(11, weight: .bold))
                            .foregroundStyle(Palette.green)
                            .lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(AppModel.clock(model.elapsed))
                                .font(AppFont.mono(14))
                                .foregroundStyle(theme.text)
                        }
                    }
                    Spacer()
                    LiveDot()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        )
    }
}

#Preview {
    let model = AppModel()
    model.startQueue(SampleData.tiles(for: "woodlands_ckpt")[1])
    return QueueTrackView()
        .environment(model)
        .environment(\.theme, Theme.dark)
        .preferredColorScheme(.dark)
}
