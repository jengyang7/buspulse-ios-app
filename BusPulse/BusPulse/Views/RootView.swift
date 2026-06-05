//
//  RootView.swift
//  BusPulse
//
//  Top-level shell: auth gate, custom tab bar, full-screen flows, mini-pill.
//  Mirrors the prototype's single-screen `view` switch.
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            switch model.flow {
            case .auth:
                AuthView()
                    .transition(.opacity)

            case .detail(let tile):
                RouteDetailView(tile: tile)
                    .transition(.move(edge: .trailing))

            case .track:
                QueueTrackView()
                    .transition(.move(edge: .bottom))

            case .done:
                QueueDoneView()
                    .transition(.opacity)

            case nil:
                tabbedContent
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.flow)
        // Coming back from the background, the tick loop was frozen — resync the
        // queue timer to wall-clock time so it reflects the time spent away.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.syncElapsed() }
        }
    }

    // MARK: - Tabbed content (Live / Stats / Profile / Settings)

    private var tabbedContent: some View {
        @Bindable var model = model
        // Native iOS 26 TabView gives a floating Liquid Glass bar and scroll-to-
        // minimize behavior. The mini-pill rides in the bottom accessory slot,
        // which the system morphs with the bar.
        let tabs = TabView(selection: $model.tab) {
            Tab(Strings.t("liveTab", model.language), systemImage: "bus.fill", value: AppTab.live) {
                LiveView()
            }
            Tab(Strings.t("statsTab", model.language), systemImage: "chart.bar.fill", value: AppTab.stats) {
                StatsView()
            }
            Tab("Profile", systemImage: "person.fill", value: AppTab.profile) {
                ProfileView()
            }
            Tab(Strings.t("settingsTab", model.language), systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(Palette.gold)
        .tabBarMinimizeBehavior(.onScrollDown)

        // Only attach the accessory when a queue is actually minimized — an empty
        // accessory still draws a glass container, so we drop the modifier itself.
        return Group {
            if model.minimized, model.active != nil {
                tabs.tabViewBottomAccessory { MiniPill() }
            } else {
                tabs
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
        .environment(\.theme, Theme.dark)
        .preferredColorScheme(.dark)
}
