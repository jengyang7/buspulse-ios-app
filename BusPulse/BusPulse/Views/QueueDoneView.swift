//
//  QueueDoneView.swift
//  BusPulse
//
//  Boarding confirmation — wait contributed, report verified, points awarded.
//  Reference: the `view === "done"` block in App.jsx.
//

import SwiftUI

struct QueueDoneView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        guard let active = model.active else { return AnyView(EmptyView()) }
        return AnyView(content(active))
    }

    private func content(_ active: RouteTile) -> some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle().fill(Palette.green.opacity(0.15)).frame(width: 96, height: 96)
                Text("✓").font(.system(size: 44, weight: .bold)).foregroundStyle(Palette.green)
            }
            .padding(.bottom, 18)

            Text(AppModel.clock(model.elapsed))
                .font(AppFont.mono(40))
                .foregroundStyle(theme.text)
            Text("added to \(active.badge)'s live wait")
                .font(AppFont.body(13))
                .foregroundStyle(theme.muted)
                .padding(.bottom, 22)

            ThemedCard {
                VStack(spacing: 12) {
                    row("Report verified", "GPS + motion ✓", Palette.green)
                    row("Queue estimate updated", "\(active.low)–\(active.high)m", theme.text)
                    row("Visible to riders", "\(active.reports + 9) commuters", theme.text)
                }
            }
            .padding(.horizontal, 16)

            Text("+15 pts for an accurate report · 🔥 4-day streak")
                .font(AppFont.body(12, weight: .semibold))
                .foregroundStyle(Palette.gold)
                .padding(.vertical, 18)

            Spacer()

            Button { model.reset() } label: {
                Text("Back to live queues")
                    .font(AppFont.body(15, weight: .bold))
                    .foregroundStyle(Color(hex: "#1A1A1A"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Palette.lime)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
    }

    private func row(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        HStack {
            Text(label).font(AppFont.body(13)).foregroundStyle(theme.muted)
            Spacer()
            Text(value).font(AppFont.body(13, weight: .bold)).foregroundStyle(valueColor)
        }
    }
}

#Preview {
    let model = AppModel()
    model.startQueue(SampleData.tiles(for: "woodlands_ckpt")[1])
    return QueueDoneView()
        .environment(model)
        .environment(\.theme, Theme.dark)
        .preferredColorScheme(.dark)
}
