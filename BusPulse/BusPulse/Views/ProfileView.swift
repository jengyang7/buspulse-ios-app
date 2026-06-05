//
//  ProfileView.swift
//  BusPulse
//
//  Profile tab — pro card, stat grid, recent trips.
//  Reference: screenshot/profile.png and the `Profile` component in App.jsx.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    private var initials: String {
        model.profileName.split(separator: " ").compactMap { $0.first }.prefix(2)
            .map(String.init).joined().uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Profile")
                .font(AppFont.body(15, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)

            ScrollView {
                VStack(spacing: 12) {
                    proCard
                    statGrid
                    recentTrips
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(theme.bg)
        .task { await model.loadProfile() }
    }

    private var proCard: some View {
        ThemedCard {
            HStack(spacing: 14) {
                Avatar(initials: initials, size: 60)
                VStack(alignment: .center, spacing: 4) {
                    Text(model.profileName).font(AppFont.body(17, weight: .bold)).foregroundStyle(theme.text)
                    Text(model.profileEmail).font(AppFont.body(12.5)).foregroundStyle(theme.muted)
                    HStack(spacing: 6) {
                        chip("PRO", tint: Palette.gold)
                        chip("Lv 7", tint: Palette.blue)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(AppFont.body(11, weight: .heavy)).tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(tint.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            statCard("\(model.avgWaitMin)m", "avg wait")
            statCard("\(model.tripsLogged)", "trips logged")
            statCard("\(model.reportsShared)", "reports shared")
            statCard("🌿 \(model.rewardPoints.formatted())", "reward pts")
        }
    }

    private func statCard(_ value: String, _ label: String) -> some View {
        ThemedCard {
            VStack(spacing: 6) {
                Text(value).font(AppFont.display(24)).foregroundStyle(theme.text)
                Text(label).font(AppFont.body(11.5)).foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var recentTrips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT TRIPS")
                .font(AppFont.body(11, weight: .bold)).tracking(0.5)
                .foregroundStyle(theme.muted)
                .padding(.top, 6)
            if model.recentTrips.isEmpty {
                ThemedCard(padding: 16) {
                    Text("No trips yet — start a queue and tap “I've boarded” to log your first.")
                        .font(AppFont.body(12.5))
                        .foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(model.recentTrips) { trip in
                ThemedCard(padding: 12) {
                    HStack(spacing: 12) {
                        MiniBadge(badge: trip.badge, colorHex: trip.colorHex, side: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(trip.op) → \(trip.to)")
                                .font(AppFont.body(13.5, weight: .bold)).foregroundStyle(theme.text)
                            Text(trip.when).font(AppFont.body(11.5)).foregroundStyle(theme.muted)
                        }
                        Spacer()
                        Text(trip.wait).font(AppFont.mono(16)).foregroundStyle(theme.text)
                    }
                }
            }
        }
    }
}

// MARK: - Avatar

struct Avatar: View {
    let initials: String
    var size: CGFloat = 52

    var body: some View {
        Text(initials)
            .font(AppFont.display(size * 0.38))
            .foregroundStyle(Color(hex: "#1A1A1A"))
            .frame(width: size, height: size)
            .background(Palette.gold)
            .clipShape(Circle())
    }
}

#Preview {
    ProfileView()
        .environment(AppModel())
        .environment(\.theme, Theme.dark)
        .preferredColorScheme(.dark)
}
