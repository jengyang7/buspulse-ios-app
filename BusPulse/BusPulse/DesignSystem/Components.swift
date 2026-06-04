//
//  Components.swift
//  BusPulse
//
//  Reusable UI ported from the prototype's small components
//  (Badge, Crowd, Chips, seg buttons, cards, the pulsing live dot).
//

import SwiftUI

// MARK: - Themed card container

struct ThemedCard<Content: View>: View {
    @Environment(\.theme) private var theme
    var padding: CGFloat = 16
    var radius: CGFloat = Radius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(theme.line, lineWidth: 1)
            )
    }
}

// MARK: - Glass icon button (nav-bar back / minimize controls)

/// Circular icon control rendered with the iOS 26 Liquid Glass button style.
/// Replaces the hand-built `theme.card` + stroke icon buttons in the nav bars.
struct GlassIconButton: View {
    let system: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}

// MARK: - Operator badge

struct OperatorBadge: View {
    let tile: RouteTile
    var large = false

    private var side: CGFloat { large ? 68 : 54 }
    private var radius: CGFloat { large ? Radius.badgeLarge : Radius.badge }

    private var fontSize: CGFloat {
        switch tile.badge.count {
        case ...2: large ? 28 : 18
        case 3:    large ? 23 : 15
        default:   large ? 18 : 12.5
        }
    }

    var body: some View {
        Text(tile.badge)
            .font(AppFont.display(fontSize))
            .foregroundStyle(tile.badgeForeground)
            .frame(width: side, height: side)
            .background(tile.badgeBackground)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                // AC7 white badge needs a hairline in light mode.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(tile.badge == "AC7" ? Color.black.opacity(0.18) : .clear, lineWidth: 1)
            )
    }
}

/// Lighter badge for list rows in Stats / Profile (square, smaller).
struct MiniBadge: View {
    let badge: String
    let colorHex: String
    var side: CGFloat = 36

    private var background: Color { badge == "AC7" ? .white : Color(hex: colorHex) }
    private var foreground: Color {
        if badge == "AC7" { return Color(hex: "#1A1A1A") }
        return OperatorColor.wantsDarkText(on: colorHex) ? Color(hex: "#1A1A1A") : .white
    }

    var body: some View {
        Text(badge)
            .font(AppFont.display(11))
            .foregroundStyle(foreground)
            .frame(width: side, height: side)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Crowd indicator

/// Just the three ascending bars, coloured by crowd level (no text label).
struct CrowdBars: View {
    @Environment(\.theme) private var theme
    let level: CrowdLevel
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .bottom, spacing: 2 * scale) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level.bars ? level.color : theme.line)
                    .frame(width: 3 * scale, height: (5 + CGFloat(i) * 3) * scale)
            }
        }
    }
}

struct CrowdIndicator: View {
    let level: CrowdLevel
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            CrowdBars(level: level)
            Text(label)
                .font(AppFont.body(12, weight: .bold))
                .foregroundStyle(level.color)
        }
    }
}

// MARK: - Route line chips

struct LineChips: View {
    let tile: RouteTile
    var small = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(tile.lines, id: \.self) { line in
                Text(line)
                    .font(AppFont.display(small ? 11 : 13))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .foregroundStyle(tile.color)
                    .background(tile.color.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .stroke(tile.color.opacity(0.36), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }
        }
    }
}

// MARK: - Segmented toggle (direction / language / theme)

struct SegmentedToggle<T: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(AppFont.body(12.5, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(isOn ? Color(hex: "#1A1A1A") : theme.muted)
                        .background(isOn ? Palette.gold : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }
}

// MARK: - Pulsing live dot

struct LiveDot: View {
    var size: CGFloat = 8
    var color: Color = Palette.green
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(pulsing ? 1.0 : 0.7)
            .opacity(pulsing ? 1.0 : 0.55)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

// MARK: - Side tag (SG / MY)

struct SideTag: View {
    @Environment(\.theme) private var theme
    let side: Side
    var small = false

    private var tint: Color { side == .sg ? Palette.blue : Palette.gold }

    var body: some View {
        Text(side.rawValue)
            .font(AppFont.body(small ? 10 : 11, weight: .heavy))
            .tracking(0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
    }
}

// MARK: - Wordmark

struct Wordmark: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            Text("Bus").foregroundStyle(theme.text)
            Text("Pulse").foregroundStyle(Palette.gold)
        }
        .font(AppFont.display(size))
    }
}
