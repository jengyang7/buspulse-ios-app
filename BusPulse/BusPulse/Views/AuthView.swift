//
//  AuthView.swift
//  BusPulse
//
//  Sign in / sign up gate.
//  Reference: screenshot/login.png and the `view === "auth"` block in App.jsx.
//

import SwiftUI

struct AuthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    private enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Wordmark(size: 30)
                Text(Strings.t("tagline", model.language))
                    .font(AppFont.body(13))
                    .foregroundStyle(theme.muted)
            }
            .padding(.bottom, 26)

            VStack(spacing: 12) {
                SegmentedToggle(
                    options: [(Mode.signIn, "Sign in"), (Mode.signUp, "Sign up")],
                    selection: $mode
                )

                googleButton
                divider

                field("Email", text: $email, secure: false)
                field("Password", text: $password, secure: true)
                if mode == .signUp {
                    field("Confirm password", text: $confirm, secure: true)
                }
                if mode == .signIn {
                    HStack {
                        Spacer()
                        Button("Forgot password?") {}
                            .font(AppFont.body(12, weight: .semibold))
                            .foregroundStyle(theme.muted)
                    }
                }

                Button { model.signIn() } label: {
                    Text(mode == .signIn ? "Sign in" : "Create account")
                        .font(AppFont.body(15, weight: .bold))
                        .foregroundStyle(Color(hex: "#1A1A1A"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Palette.lime)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)

            Spacer()

            Text("By continuing, you agree to our Terms & Privacy Policy")
                .font(AppFont.body(11))
                .foregroundStyle(theme.faint)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
    }

    private var googleButton: some View {
        Button {} label: {
            HStack(spacing: 10) {
                Text("G").font(AppFont.display(16)).foregroundStyle(Palette.blue)
                Text("Continue with Google").font(AppFont.body(14, weight: .bold))
            }
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.card2)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        HStack(spacing: 10) {
            theme.line.frame(height: 1)
            Text("or").font(AppFont.body(11)).foregroundStyle(theme.faint)
            theme.line.frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private func field(_ placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }
        }
        .font(AppFont.body(14))
        .foregroundStyle(theme.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(theme.bg2)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    AuthView()
        .environment(AppModel())
        .environment(\.theme, Theme.dark)
        .preferredColorScheme(.dark)
}
