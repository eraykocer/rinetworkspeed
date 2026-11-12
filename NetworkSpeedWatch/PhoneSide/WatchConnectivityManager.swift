//
//  WatchConnectivityManager.swift
//  rinetworkspeed
//
//  Manages WatchConnectivity session on the iOS side.
//  Sends real-time network stats to the paired Apple Watch.
//

import Foundation
import WatchConnectivity
import Combine
import UIKit

final class WatchConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {

    static let shared = WatchConnectivityManager()

    @Published var isWatchReachable: Bool = false

    // Accumulated context so speed + usage are always sent together
    private var latestContext: [String: Any] = [
        "downloadSpeed": 0.0,
        "uploadSpeed": 0.0,
        "todayWifi": UInt64(0),
        "todayCellular": UInt64(0),
        "activeInterface": "none"
    ]

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Public API

    /// Called each time NetworkStatsMonitor.sample() fires.
    func updateSpeeds(download: Double, upload: Double, activeInterface: NetworkInterface) {
        latestContext["downloadSpeed"] = download
        latestContext["uploadSpeed"] = upload
        latestContext["activeInterface"] = activeInterface.rawValue
        sendToWatch()
    }

    /// Called each time DataUsageMonitor.refreshUsage() fires.
    func updateDataUsage(todayWifi: UInt64, todayCellular: UInt64) {
        latestContext["todayWifi"] = todayWifi
        latestContext["todayCellular"] = todayCellular
        // Data usage changes slowly — only update application context, no live message
        pushApplicationContext()
    }

    // MARK: - Private

    private func sendToWatch() {
        guard WCSession.default.activationState == .activated else { return }
        guard WCSession.default.isPaired else { return }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(latestContext, replyHandler: nil) { [weak self] _ in
                self?.pushApplicationContext()
            }
        } else {
            pushApplicationContext()
        }
    }

    private func pushApplicationContext() {
        guard WCSession.default.activationState == .activated else { return }
        guard WCSession.default.isPaired else { return }
        // updateApplicationContext requires values to be Codable-compatible types;
        // UInt64 is not directly supported — convert to Int64 which fits in Int.
        var safeContext: [String: Any] = latestContext
        if let wifi = latestContext["todayWifi"] as? UInt64 {
            safeContext["todayWifi"] = Int64(bitPattern: wifi)
        }
        if let cellular = latestContext["todayCellular"] as? UInt64 {
            safeContext["todayCellular"] = Int64(bitPattern: cellular)
        }
        try? WCSession.default.updateApplicationContext(safeContext)
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }

    /// Received when the Watch requests the iOS app to be opened.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["openApp"] as? Bool == true {
            // Bring the app to foreground — UIApplication is available on iOS only
            DispatchQueue.main.async {
                _ = UIApplication.shared // No-op; app is already in foreground when reachable
            }
        }
    }
}
