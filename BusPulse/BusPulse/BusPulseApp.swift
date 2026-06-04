//
//  BusPulseApp.swift
//  BusPulse
//
//  Created by Jayden Kong on 3/6/26.
//

import SwiftUI

@main
struct BusPulseApp: App {
    @State private var model = AppModel(dataSource: SupabaseDataSource())

    init() {
        FontRegistration.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.theme, model.theme)
                .preferredColorScheme(model.colorScheme)
                .task { await model.load() }
        }
    }
}
