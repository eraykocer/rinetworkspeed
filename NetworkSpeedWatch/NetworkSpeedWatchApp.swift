//
//  NetworkSpeedWatchApp.swift
//  NetworkSpeedWatch
//
//  Watch app entry point. Initialises the WCSession via WatchSessionManager.
//

import SwiftUI

@main
struct NetworkSpeedWatchApp: App {

    init() {
        // Activate WatchConnectivity session as early as possible
        _ = WatchSessionManager.shared
    }

    var body: some Scene {
        WindowGroup {
            WatchNetworkView()
                .environmentObject(WatchSessionManager.shared)
        }
    }
}
