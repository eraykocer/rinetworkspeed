//
//  GetPingIntent.swift
//  rinetworkspeed
//
//  "Ping değerim ne?" — Measures round-trip latency to 1.1.1.1 and returns a
//  quality classification (Mükemmel / İyi / Orta / Zayıf).
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
        let dialog  = "Connection latency is \(ms) ms, connection quality: \(quality)."
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }

    // MARK: - Private

    /// Sends 3 HEAD requests to 1.1.1.1 and returns the average RTT in milliseconds.
    private func measurePing() async -> Double {
        guard let url = URL(string: "https://1.1.1.1") else { return -1 }

        var request              = URLRequest(url: url)
        request.httpMethod       = "HEAD"
        request.timeoutInterval  = 5
        request.cachePolicy      = .reloadIgnoringLocalCacheData

        let config                            = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest      = 5
        config.timeoutIntervalForResource     = 5
        config.waitsForConnectivity           = false
        let session                           = URLSession(configuration: config)

        var samples: [Double] = []
        for _ in 0..<3 {
            let start = Date()
            if let (_, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse,
               (200...599).contains(http.statusCode)
            {
                samples.append(Date().timeIntervalSince(start) * 1_000)
            }
        }

        guard !samples.isEmpty else { return -1 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    private func pingQuality(_ ms: Double) -> String {
        switch ms {
        case ..<0:    return "No Connection"
        case 0..<30:  return "Excellent"
        case 30..<80: return "Good"
        case 80..<150: return "Fair"
        default:      return "Poor"
        }
    }
}
