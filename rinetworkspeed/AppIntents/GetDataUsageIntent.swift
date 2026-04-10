//
//  GetDataUsageIntent.swift
//  rinetworkspeed
//
//  "Bugün ne kadar veri kullandım?" — Reports today's WiFi + Cellular usage via Siri.
//  DataUsageMonitor writes current-day totals to the shared App Group defaults
//  (keys "intentTodayWifi" / "intentTodayCellular") so this intent works even
//  when the main app is closed.
//

import AppIntents

struct GetDataUsageIntent: AppIntent {

    static let title: LocalizedStringResource = "Show Data Usage"
    static let description                    = IntentDescription(
        "Gets today's WiFi and Cellular data usage.",
        categoryName: "Network"
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let shared = UserDefaults(suiteName: "group.com.rinetworkspeed")

        // Values are persisted as Int (64-bit on iOS) by DataUsageMonitor
        let wifiBytes     = UInt64(max(0, shared?.integer(forKey: "intentTodayWifi")     ?? 0))
        let cellularBytes = UInt64(max(0, shared?.integer(forKey: "intentTodayCellular") ?? 0))
        let totalBytes    = wifiBytes + cellularBytes

        let wifiStr     = formatIntentBytes(wifiBytes)
        let cellularStr = formatIntentBytes(cellularBytes)
        let totalStr    = formatIntentBytes(totalBytes)

        let dialog = "Today you used \(wifiStr) WiFi and \(cellularStr) Cellular. Total: \(totalStr)."
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
