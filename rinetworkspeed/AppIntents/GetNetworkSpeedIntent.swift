//
//  GetNetworkSpeedIntent.swift
//  rinetworkspeed
//
//  "What is my internet speed?" — Returns the current download / upload speed via Siri.
//  Prefers cached values written by NetworkStatsMonitor (shared UserDefaults,
//  updated every ~0.5 s while the app is running). Falls back to a live 1-second
//  kernel measurement when the cache is older than 10 s.
//

import AppIntents

struct GetNetworkSpeedIntent: AppIntent {

    static let title: LocalizedStringResource       = "Show Network Speed"
    static let description                          = IntentDescription(
        "Gets the current download and upload speed.",
        categoryName: "Network"
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (download, upload) = await resolveSpeed()

        let downStr = formatIntentSpeed(download)
        let upStr   = formatIntentSpeed(upload)
        let dialog  = "Your download speed is \(downStr) and upload speed is \(upStr)."

        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }

    // MARK: - Private

    private func resolveSpeed() async -> (Double, Double) {
        let shared    = UserDefaults(suiteName: "group.rinetworkspeedapp")
        let lastTs    = shared?.double(forKey: "lastUpdated") ?? 0
        let isRecent  = Date().timeIntervalSince1970 - lastTs < 10

        if isRecent {
            let down = shared?.double(forKey: "downloadSpeed") ?? 0
            let up   = shared?.double(forKey: "uploadSpeed")   ?? 0
            if down > 0 || up > 0 { return (down, up) }
        }

        // Live 1-second measurement via getifaddrs
        let snap1 = captureNetworkSnapshot()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let snap2 = captureNetworkSnapshot()

        let down = snap2.bytesIn  >= snap1.bytesIn  ? Double(snap2.bytesIn  - snap1.bytesIn)  / 1.0 : 0
        let up   = snap2.bytesOut >= snap1.bytesOut ? Double(snap2.bytesOut - snap1.bytesOut) / 1.0 : 0
        return (down, up)
    }
}
