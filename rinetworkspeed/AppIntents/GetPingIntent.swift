//
//  GetPingIntent.swift
//  rinetworkspeed
//
//  "What is my ping?" — Measures round-trip latency to 1.1.1.1 and returns a
//  quality classification (Excellent / Good / Fair / Poor).
//

import AppIntents
import Foundation

struct GetPingIntent: AppIntent {

    static let title: LocalizedStringResource = "Show Ping"
    static let description                    = IntentDescription(
        "Measures network latency (ping) and evaluates connection quality.",
        categoryName: "Network"
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let latency = await measurePing()

        if latency < 0 {
            return .result(dialog: "Could not connect. Please check your network connection.")
        }

        let ms      = Int(latency.rounded())
        let quality = pingQuality(latency)
        return .result(dialog: "Connection latency is \(ms) ms, connection quality: \(quality).")
    }

    // MARK: - Private

    /// Average TCP handshake time to 1.1.1.1 over three samples, in milliseconds.
    /// Uses the same measurement as the Ping Monitor, so the numbers match.
    private func measurePing() async -> Double {
        var samples: [Double] = []
        for _ in 0..<3 {
            let ms = await PingMonitor.tcpConnectTime(host: "1.1.1.1", port: 443, timeout: 5)
            if ms >= 0 { samples.append(ms) }
        }
        guard !samples.isEmpty else { return -1 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    private func pingQuality(_ ms: Double) -> String {
        switch ms {
        case ..<0:    return String(localized: "No Connection")
        case 0..<30:  return String(localized: "Excellent")
        case 30..<80: return String(localized: "Good")
        case 80..<150: return String(localized: "Fair")
        default:      return String(localized: "Poor")
        }
    }
}
