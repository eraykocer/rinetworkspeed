//
//  ModemLine.swift
//  rinetworkspeed
//
//  Compares three numbers: the advertised plan, the modem's line rate (DSL
//  sync) and measured speed tests, to tell whether the line or the home
//  network limits the speed. Also keeps the last modem reading for the ISP report.
//

import Foundation

nonisolated struct LineComparison: Equatable, Sendable {
    nonisolated enum Verdict: Equatable, Sendable {
        /// The line syncs well below the plan: tests can never reach it.
        case lineBelowPlan
        /// The line is fine but tests fall well short of it: Wi-Fi, the
        /// router or other devices at home.
        case homeBelowLine
        /// Line, plan and tests agree.
        case consistent
        /// No advertised plan entered.
        case needsPlan
        /// No recent Wi-Fi speed tests.
        case needsTests
    }

    /// A line below this share of the plan counts as below it. Sync rates
    /// include protocol overhead, so a healthy line sits a little above the plan.
    static let lineShareOfPlan = 0.9
    /// Tests below this share of the line rate leave a gap inside the home.
    /// Overhead alone costs roughly 10–15 %.
    static let testShareOfLine = 0.7

    /// All in megabits per second.
    let lineMbps: Double
    let planMbps: Double?
    let testMbps: Double?

    var verdict: Verdict {
        if let planMbps, lineMbps < planMbps * Self.lineShareOfPlan { return .lineBelowPlan }
        if let testMbps, testMbps < lineMbps * Self.testShareOfLine { return .homeBelowLine }
        if planMbps == nil { return .needsPlan }
        if testMbps == nil { return .needsTests }
        return .consistent
    }

    /// Median download of the latest Wi-Fi tests (up to 10, last 14 days).
    @MainActor
    static func recentWiFiDownloadMbps(_ results: [SpeedTestResult], now: Date = Date()) -> Double? {
        let downloads = results
            .filter { $0.connection == .wifi && now.timeIntervalSince($0.date) < 14 * 86_400 }
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map { $0.downloadSpeed * 8 / 1_000_000 }
            .sorted()
        guard !downloads.isEmpty else { return nil }
        let middle = downloads.count / 2
        return downloads.count.isMultiple(of: 2) ? (downloads[middle - 1] + downloads[middle]) / 2 : downloads[middle]
    }
}

/// The last successful modem reading, kept for the ISP report.
nonisolated enum ModemReadingStore {
    private static let key = "lastModemReading"
    /// Older readings are not put in a report.
    static let maximumAge: TimeInterval = 60 * 86_400

    static func save(_ reading: ModemReading, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(reading) else { return }
        defaults.set(data, forKey: key)
    }

    static func load(from defaults: UserDefaults = .standard) -> ModemReading? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ModemReading.self, from: data)
    }

    /// A recent DSL reading, or nil.
    static func recentLineReading(from defaults: UserDefaults = .standard, now: Date = Date()) -> ModemReading? {
        guard let reading = load(from: defaults), reading.isLineRate, reading.downstreamMbps != nil,
              now.timeIntervalSince(reading.date) < maximumAge else { return nil }
        return reading
    }
}
