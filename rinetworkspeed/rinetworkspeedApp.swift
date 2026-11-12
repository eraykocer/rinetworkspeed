//
//  rinetworkspeedApp.swift
//  rinetworkspeed
//
//  Created by Eray Koçer on 9.04.2026.
//

import SwiftUI

@main
struct rinetworkspeedApp: App {

    init() {
        PurchaseManager.shared.configure()
        // The notification delegate must be set before launch finishes, or a
        // tap that cold-launches the app is never delivered to it.
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
