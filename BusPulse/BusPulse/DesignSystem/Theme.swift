//
//  Theme.swift
//  BusPulse
//
//  Design tokens ported 1:1 from the React prototype
//  (busqueue-ui/src/App.jsx — see the `.screen.dark` / `.screen.light` CSS).
//

import SwiftUI

// MARK: - Hex helper

extension Color {
    /// Create a Color from a hex string like "#0E1014" or "0E1014".
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Semantic palette (theme-independent)

enum Palette {
    static let gold   = Color(hex: "#FFB23E")
    static let lime   = Color(hex: "#A6E25C")
    static let green  = Color(hex: "#3AD29F")
    static let orange = Color(hex: "#FF9F45")
    static let red    = Color(hex: "#FF6B6B")
    static let blue   = Color(hex: "#5BA8FF")
}

// MARK: - Operator colours

enum OperatorColor {
    static let cw      = Color(hex: "#F2C200") // Causeway Link
    static let sbs     = Color(hex: "#7C5CFF") // SBS / SMRT family
    static let smrt    = Color(hex: "#E23B3B") // SMRT 950
    static let express = Color(hex: "#1F9E6B") // Causeway Express / AC7

    /// AC7 and CW/lime backgrounds want dark text on top.
    static func wantsDarkText(on hex: String) -> Bool {
        ["#F2C200", "#A6E25C", "F2C200", "A6E25C"].contains(hex)
    }
}

// MARK: - Theme (light / dark token sets)

struct Theme {
    let bg: Color
    let bg2: Color
    let card: Color
    let card2: Color
    let line: Color
    let text: Color
    let muted: Color
    let faint: Color

    static let dark = Theme(
        bg:    Color(hex: "#0E1014"),
        bg2:   Color(hex: "#141821"),
        card:  Color(hex: "#191D27"),
        card2: Color(hex: "#20252F"),
        line:  Color(hex: "#2A303C"),
        text:  Color(hex: "#ECEEF3"),
        muted: Color(hex: "#8089A0"),
        faint: Color(hex: "#5A6172")
    )

    static let light = Theme(
        bg:    Color(hex: "#F1F4F9"),
        bg2:   Color(hex: "#FFFFFF"),
        card:  Color(hex: "#FFFFFF"),
        card2: Color(hex: "#EDF0F6"),
        line:  Color(hex: "#E2E7EF"),
        text:  Color(hex: "#161A22"),
        muted: Color(hex: "#5E6678"),
        faint: Color(hex: "#A0A7B6")
    )
}

enum AppearanceMode: String, CaseIterable {
    case light, dark
    var theme: Theme { self == .dark ? .dark : .light }
}

// MARK: - Environment plumbing

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.dark
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Fonts
//
// Fonts must be added to the target and listed in Info.plist `UIAppFonts`:
//   Bricolage Grotesque, DM Sans, JetBrains Mono.
// These helpers fall back to system fonts gracefully if not yet installed.

enum AppFont {
    /// Display / headings / badges / big numbers. (Bricolage Grotesque ExtraBold)
    static func display(_ size: CGFloat) -> Font {
        .custom("BricolageGrotesque-ExtraBold", size: size)
    }

    /// Body / UI text. Maps the requested weight to a bundled DM Sans face.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(dmSansName(weight), size: size)
    }

    /// Wait ranges and the live queue timer. (JetBrains Mono)
    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let name = weight == .medium || weight == .regular
            ? "JetBrainsMono-Medium" : "JetBrainsMono-Bold"
        return .custom(name, size: size)
    }

    /// Pick the nearest available DM Sans static instance for a SwiftUI weight.
    private static func dmSansName(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: "DMSans-Regular"
        case .medium:                               "DMSans-Medium"
        case .semibold:                             "DMSans-SemiBold"
        case .bold:                                 "DMSans-Bold"
        case .heavy, .black:                        "DMSans-ExtraBold"
        default:                                    "DMSans-Regular"
        }
    }
}

/// Registers all bundled `.ttf` files with CoreText at launch.
/// Avoids needing a `UIAppFonts` array in a generated Info.plist.
enum FontRegistration {
    private static var done = false

    static func registerBundledFonts() {
        guard !done else { return }
        done = true
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

// MARK: - Shared metrics

enum Radius {
    static let tile: CGFloat = 18
    static let badge: CGFloat = 16
    static let badgeLarge: CGFloat = 20
    static let card: CGFloat = 20
    static let chip: CGFloat = 8
    static let control: CGFloat = 14
}
