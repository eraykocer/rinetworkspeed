//
//  RunSpeedTestIntent.swift
//  rinetworkspeed
//
//  "Run speed test" — Runs a full download / upload test and reports results.
//  Delegates to SpeedTestManager which is @MainActor. The full test can take
//  up to ~60 s; it completes reliably in the Shortcuts app. Siri may time out
//  for very slow connections but the result is saved to SpeedTestManager.history.
//

import AppIntents

struct RunSpeedTestIntent: AppIntent {

    static let title: LocalizedStringResource = "Run Speed Test"
    static let description                    = IntentDescription(
        "Runs a real-time download / upload speed test.",
        categoryName: "Network"
    )
    // Runs entirely in the background — no need to open the UI.
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = SpeedTestManager()
        await manager.startTest()

        switch manager.state {
        case .finished:
            // Same unit as the in-app result (megabits per second).
            let score   = SpeedTestScore(
                downloadBytesPerSecond: manager.finalDownload,
                uploadBytesPerSecond: manager.finalUpload,
                ping: manager.ping,
                jitter: manager.jitter
            )
            let down    = score.downloadMbps.formatted(.number.precision(.fractionLength(1)))
            let up      = score.uploadMbps.formatted(.number.precision(.fractionLength(1)))
            let ping    = Int(manager.ping.rounded())
            return .result(dialog: "Speed test complete. Download: \(down) Mbps, upload: \(up) Mbps, latency: \(ping) ms.")

        case .failed:
            return .result(dialog: "Speed test failed. Please check your connection and try again.")

        default:
            manager.cancelTest()
            return .result(dialog: "Speed test was cancelled or could not complete.")
        }
    }
}
