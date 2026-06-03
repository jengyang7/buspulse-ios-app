//
//  LiveView.swift
//  BusPulse
//
//  Home / Live tab — direction segment, location picker, live route tiles.
//  Reference: screenshot/home.png and the `view === "live"` block in App.jsx.
//

import SwiftUI

struct LiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var pickerOpen = false
    @State private var appeared = false

    var body: some View {
        @Bindable var model = model
        // Only the route tiles scroll; the header is pinned via safeAreaInset so
        // the scroll-edge fade happens behind the opaque header, not over the tiles.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 12) {
                    ForEach(Array(model.tiles.enumerated()), id: \.element.id) { index, tile in
                        RouteTileRow(tile: tile)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)
                            .animation(.easeOut(duration: 0.5).delay(Double(index) * 0.07), value: appeared)
                    }
                }
                .padding(.top, 4)
                .id(model.selectedLocationId)       // re-fire stagger when the location changes
                .onAppear { appeared = true }

                Text(Strings.t("hint", model.language))
                    .font(AppFont.body(12))
                    .foregroundStyle(theme.faint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Pinned header — wordmark/greeting, direction, location, live banner.
            VStack(alignment: .leading, spacing: 0) {
                header

                SegmentedToggle(
                    options: Direction.allCases.map { ($0, $0.label) },
                    selection: Binding(
                        get: { model.direction },
                        set: { model.direction = $0; pickerOpen = false }
                    )
                )
                .padding(.bottom, 8)

                locationBar
                if pickerOpen { locationPicker }

                liveBanner
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .background(theme.bg)
        }
        .background(theme.bg)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Wordmark(size: 22)
                Text("\(model.greeting), \(firstName)")
                    .font(AppFont.body(11.5))
                    .foregroundStyle(theme.muted)
            }
            Spacer()
            HStack(spacing: 4) {
                Text("🌿")
                Text(SampleData.rewardPoints.formatted())
                    .font(AppFont.body(11, weight: .bold))
                    .foregroundStyle(theme.text)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.card)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.bottom, 14)
    }

    private var firstName: String {
        String(model.profileName.split(separator: " ").first ?? "")
    }

    // MARK: Location bar + picker

    private var locationBar: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { pickerOpen.toggle() }
        } label: {
            HStack(spacing: 10) {
                Text("📍")
                Text(model.selectedLocation.name)
                    .font(AppFont.body(15, weight: .bold))
                    .foregroundStyle(theme.text)
                Spacer()
                SideTag(side: model.selectedLocation.side)
                Image(systemName: pickerOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(theme.card)
            .overlay(RoundedRectangle(cornerRadius: Radius.tile).stroke(theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.tile))
        }
        .buttonStyle(.plain)
    }

    private var locationPicker: some View {
        VStack(spacing: 0) {
            ForEach(SampleData.locations(for: model.direction)) { loc in
                Button {
                    model.selectLocation(loc.id)
                    withAnimation(.easeInOut(duration: 0.2)) { pickerOpen = false }
                } label: {
                    HStack {
                        Text(loc.name)
                            .font(AppFont.body(14))
                            .foregroundStyle(loc.id == model.selectedLocationId ? Palette.gold : theme.text)
                        Spacer()
                        SideTag(side: loc.side, small: true)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                if loc.id != SampleData.locations(for: model.direction).last?.id {
                    theme.line.frame(height: 1)
                }
            }
        }
        .background(theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.line, lineWidth: 1))
        .padding(.top, 8)
    }

    private var liveBanner: some View {
        HStack(spacing: 7) {
            LiveDot()
            Text(Strings.t("live", model.language, model.totalReports))
                .font(AppFont.body(12))
                .foregroundStyle(theme.muted)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Route tile row

private struct RouteTileRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let tile: RouteTile

    var body: some View {
        Button {
            model.openDetail(tile)
        } label: {
            HStack(spacing: 12) {
                OperatorBadge(tile: tile)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(tile.low)–\(tile.high)")
                            .font(AppFont.mono(24))
                            .foregroundStyle(tile.crowd.color)
                        Text("min")
                            .font(AppFont.body(10.5))
                            .foregroundStyle(theme.muted)
                    }
                    CrowdIndicator(level: tile.crowd,
                                   label: Strings.t(tile.crowd.labelKey, model.language))
                    Text("\(Strings.t("nextBus", model.language)) \(tile.next)m")
                        .font(AppFont.body(12))
                        .foregroundStyle(theme.muted)
                    Text("\(Estimate.liveRecorders(tile)) timing now · updated \(tile.fresh)m ago")
                        .font(AppFont.body(11))
                        .foregroundStyle(theme.faint)
                }

                Spacer(minLength: 4)

                queueButton
            }
            .padding(.init(top: 12, leading: 12, bottom: 12, trailing: 14))
            .background(theme.card)
            .overlay(RoundedRectangle(cornerRadius: Radius.tile).stroke(theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.tile))
        }
        .buttonStyle(.plain)
    }

    private var queueButton: some View {
        let disabled = model.active != nil
        return Button {
            if !disabled { model.quickQueue(tile) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill").font(.system(size: 11))
                Text("Queue").font(AppFont.body(12.5, weight: .bold))
            }
            .foregroundStyle(disabled ? theme.faint : Palette.gold)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(disabled ? theme.card2 : Palette.gold.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.badge)
                    .stroke(disabled ? theme.line : Palette.gold.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

#Preview {
    LiveView()
        .environment(AppModel())
        .environment(\.theme, Theme.dark)
        .preferredColorScheme(.dark)
}
