//
//  WatchSessionManager.swift
//  NetworkSpeedWatch
//
//  Manages the WCSession on the Watch side.
//  Receives network stats from the iOS app and publishes them to the UI.
//

import Foundation
import WatchConnectivity
import ClockKit

final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {

    static let shared = WatchSessionManager()

    @Published var downloadSpeed: Double = 0
    @Published var uploadSpeed: Double = 0
    @Published var todayWifiBytes: Int64 = 0
    @Published var todayCellularBytes: Int64 = 0
    @Published var activeInterface: String = "none"
    @Published var lastUpdate: Date = .distantPast

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Public

    func requestOpenApp() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["openApp": true], replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Private

    private func apply(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let v = data["downloadSpeed"] as? Double { self.downloadSpeed = v }
            if let v = data["uploadSpeed"]   as? Double { self.uploadSpeed   = v }
            if let v = data["todayWifi"]     as? Int64  { self.todayWifiBytes     = v }
            if let v = data["todayCellular"] as? Int64  { self.todayCellularBytes = v }
            if let v = data["activeInterface"] as? String { self.activeInterface = v }
            self.lastUpdate = Date()

            // Push live data to active complications
            let server = CLKComplicationServer.sharedInstance()
            server.activeComplications?.forEach { server.reloadTimeline(for: $0) }
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        apply(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}
