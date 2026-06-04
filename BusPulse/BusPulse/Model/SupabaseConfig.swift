//
//  SupabaseConfig.swift
//  BusPulse
//
//  Connection to the backend. Points at the LOCAL Supabase stack by default
//  (see ../../supabase). The publishable/anon key is a non-secret local default
//  that ships with every `supabase start`; swap both for the hosted project's
//  values when deploying to a real device.
//
//  Note: the iOS Simulator shares the Mac's network, so 127.0.0.1 resolves to
//  the local stack. A physical device cannot reach 127.0.0.1 — point `url` at
//  the Mac's LAN IP (and add an ATS exception) or at the hosted project.
//

import Foundation
import Supabase

enum SupabaseConfig {
    static let url = URL(string: "http://127.0.0.1:54321")!
    static let anonKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"

    static let client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
}
