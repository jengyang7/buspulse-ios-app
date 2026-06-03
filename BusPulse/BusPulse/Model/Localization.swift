//
//  Localization.swift
//  BusPulse
//
//  In-app language switching ported from the prototype's `T` object.
//  Kept as a plain dictionary (not the system String Catalog) because the
//  prototype changes language live from Settings, independent of system locale.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, zh, ms
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: "English"
        case .zh: "中文"
        case .ms: "Melayu"
        }
    }
}

enum Strings {
    /// Look up a key for a language, falling back to English.
    static func t(_ key: String, _ lang: AppLanguage) -> String {
        table[lang]?[key] ?? table[.en]?[key] ?? key
    }

    /// Keys that take a count (e.g. the live-reports banner).
    static func t(_ key: String, _ lang: AppLanguage, _ n: Int) -> String {
        let raw = t(key, lang)
        return raw.replacingOccurrences(of: "{n}", with: String(n))
    }

    private static let table: [AppLanguage: [String: String]] = [
        .en: [
            "tagline": "Real-time queue estimates from community",
            "live": "Live · {n} reports in last 10 min",
            "hint": "Tap a tile for details, or the play icon to queue instantly",
            "crowd_low": "Light", "crowd_med": "Moderate", "crowd_high": "Packed",
            "nextBus": "Next bus", "startQueue": "Start queue", "boarded": "I've boarded",
            "leftQueue": "I left the queue", "queuingNow": "Queuing now", "routeDetails": "Route details",
            "yourWaitEst": "your wait · est", "liveTab": "Live", "statsTab": "Stats",
            "settings": "Settings", "settingsTab": "Settings", "language": "Language",
            "appearance": "Appearance", "light": "Light", "dark": "Dark",
            "notifications": "Push notifications", "locationAccess": "Location access",
            "logout": "Log out", "routes": "Routes in this queue",
        ],
        .zh: [
            "tagline": "来自排队乘客的实时等待估算",
            "live": "实时 · 过去10分钟 {n} 条报告",
            "hint": "点按查看详情，或点播放图标立即排队",
            "crowd_low": "通畅", "crowd_med": "适中", "crowd_high": "拥挤",
            "nextBus": "下一班", "startQueue": "开始排队", "boarded": "我已上车",
            "leftQueue": "我离开队伍", "queuingNow": "排队中", "routeDetails": "路线详情",
            "yourWaitEst": "你的等待 · 预计", "liveTab": "实时", "statsTab": "统计",
            "settings": "设置", "settingsTab": "设置", "language": "语言",
            "appearance": "外观", "light": "浅色", "dark": "深色",
            "notifications": "推送通知", "locationAccess": "定位权限",
            "logout": "退出登录", "routes": "此队伍的路线",
        ],
        .ms: [
            "tagline": "Anggaran tunggu langsung daripada penumpang",
            "live": "Langsung · {n} laporan dalam 10 minit",
            "hint": "Ketik untuk butiran, atau ikon main untuk terus beratur",
            "crowd_low": "Lengang", "crowd_med": "Sederhana", "crowd_high": "Padat",
            "nextBus": "Bas seterusnya", "startQueue": "Mula beratur", "boarded": "Saya dah naik",
            "leftQueue": "Saya tinggalkan barisan", "queuingNow": "Sedang beratur", "routeDetails": "Butiran laluan",
            "yourWaitEst": "menunggu anda · anggar", "liveTab": "Langsung", "statsTab": "Statistik",
            "settings": "Tetapan", "settingsTab": "Tetapan", "language": "Bahasa",
            "appearance": "Penampilan", "light": "Cerah", "dark": "Gelap",
            "notifications": "Pemberitahuan tolak", "locationAccess": "Akses lokasi",
            "logout": "Log keluar", "routes": "Laluan dalam barisan ini",
        ],
    ]
}
