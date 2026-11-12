//
//  AppRouter.swift
//  rinetworkspeed
//
//  Single entry point for navigation requests that come from outside the
//  view hierarchy: notification actions, widget taps, the Control Center
//  control and deep links (rinetworkspeed://<destination>).
//

import Foundation
import Combine

enum AppDestination: String, Equatable {
    case home
    case graph
    case usage
    case tools
    case settings
    /// Opens the speed test sheet and starts a test right away.
    case speedTest = "speedtest"

    /// Tab index in `MainTabView`.
    var tab: Int {
        switch self {
        case .home, .speedTest: return 0
        case .graph: return 1
        case .usage: return 2
        case .tools: return 3
        case .settings: return 4
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    static let urlScheme = "rinetworkspeed"

    /// Set by external triggers and cleared by the view that consumes it.
    @Published var pendingDestination: AppDestination?

    private init() {
        #if DEBUG
        // Screenshot / UI review helper: launch with `-debugOpen speedtest`.
        if let raw = UserDefaults.standard.string(forKey: "debugOpen"),
           let destination = AppDestination(rawValue: raw) {
            pendingDestination = destination
        }
        #endif
    }

    func open(_ destination: AppDestination) {
        pendingDestination = destination
    }

    /// Handles `rinetworkspeed://speedtest`, `rinetworkspeed://usage`, etc.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == Self.urlScheme,
              let host = url.host(),
              let destination = AppDestination(rawValue: host.lowercased()) else {
            return false
        }
        open(destination)
        return true
    }
}
