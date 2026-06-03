//
//  SettingsView.swift
//  BusPulse
//
//  Settings tab — account, language, appearance, toggles, log out.
//  Reference: the `view === "settings"` block in App.jsx.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var editingProfile = false

    private var initials: String {
        model.profileName.split(separator: " ").compactMap { $0.first }.prefix(2)
            .map(String.init).joined().uppercased()
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Text(Strings.t("settings", model.language))
                .font(AppFont.body(15, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    accountCard

                    sectionLabel(Strings.t("language", model.language))
                    SegmentedToggle(
                        options: AppLanguage.allCases.map { ($0, $0.displayName) },
                        selection: $model.language
                    )

                    sectionLabel(Strings.t("appearance", model.language))
                    SegmentedToggle(
                        options: [
                            (AppearanceMode.light, "☀️ \(Strings.t("light", model.language))"),
                            (AppearanceMode.dark, "🌙 \(Strings.t("dark", model.language))"),
                        ],
                        selection: $model.appearance
                    )

                    toggleList

                    Button { model.logOut() } label: {
                        Text(Strings.t("logout", model.language))
                            .font(AppFont.body(14, weight: .bold))
                            .foregroundStyle(Palette.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Palette.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)

                    Text("buspulse v0.9 · made for the Causeway 🌉")
                        .font(AppFont.body(11))
                        .foregroundStyle(theme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(theme.bg)
    }

    // MARK: Account

    private var accountCard: some View {
        @Bindable var model = model
        return ThemedCard {
            HStack(spacing: 14) {
                Avatar(initials: initials, size: 52)
                if editingProfile {
                    VStack(spacing: 6) {
                        editField("Display name", text: $model.profileName)
                        editField("Email", text: $model.profileEmail)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.profileName).font(AppFont.body(16, weight: .bold)).foregroundStyle(theme.text)
                        Text(model.profileEmail).font(AppFont.body(12.5)).foregroundStyle(theme.muted)
                    }
                }
                Spacer()
                Button(editingProfile ? "Save" : "Edit") {
                    editingProfile.toggle()
                }
                .font(AppFont.body(12.5, weight: .bold))
                .foregroundStyle(editingProfile ? Color(hex: "#1A1A1A") : theme.text)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(editingProfile ? Palette.lime : theme.card2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
    }

    private func editField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(AppFont.body(13))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(theme.bg2)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Toggles

    private var toggleList: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            toggleRow("🔔 \(Strings.t("notifications", model.language))", isOn: $model.notificationsOn)
            theme.line.frame(height: 1)
            toggleRow("📍 \(Strings.t("locationAccess", model.language))", isOn: $model.locationAccessOn)
            theme.line.frame(height: 1)
            toggleRow("📡 Auto-detect boarding", isOn: $model.autoDetectBoarding)
        }
        .background(theme.card)
        .overlay(RoundedRectangle(cornerRadius: Radius.tile).stroke(theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile))
        .padding(.vertical, 18)
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label).font(AppFont.body(14)).foregroundStyle(theme.text)
        }
        .tint(Palette.green)
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppFont.body(12, weight: .bold)).tracking(0.5)
            .foregroundStyle(theme.muted)
            .padding(.top, 14).padding(.bottom, 9)
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
        .environment(\.theme, Theme.dark)
        .preferredColorScheme(.dark)
}
