//
//  rinetworkspeedApp.swift
//  rinetworkspeed
//
//  Created by Eray Koçer on 9.04.2026.
//

import SwiftUI
import WatchConnectivity

@main
struct rinetworkspeedApp: App {

    init() {
        PurchaseManager.shared.configure()
        // Start WatchConnectivity session early so the watch can receive data
        _ = WatchConnectivityManager.shared
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
