//
//  RunSpeedTestIntent.swift
//  rinetworkspeed
//
//  "Hız testi yap" — Runs a full download / upload test and reports results.
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
            let down    = formatIntentSpeed(manager.finalDownload)
            let up      = formatIntentSpeed(manager.finalUpload)
            let ping    = String(format: "%.0f ms", manager.ping)
            let dialog  = "Speed test complete. Download: \(down), upload: \(up), latency: \(ping)."
            return .result(dialog: IntentDialog(stringLiteral: dialog))

        case .failed:
            return .result(dialog: "Speed test failed. Please check your connection and try again.")

        default:
            manager.cancelTest()
            return .result(dialog: "Speed test was cancelled or could not complete.")
        }
    }
}
