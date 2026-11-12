//
//  InternetPlan.swift
//  rinetworkspeed
//
//  The speeds the user's provider advertises, and how measured results
//  compare with them. Used by the history screen and the ISP report PDF.
//

import Foundation

struct InternetPlan: Equatable {
    var provider: String
    /// Megabits per second.
    var downloadMbps: Double
    var uploadMbps: Double

    enum Key {
        static let provider = "planProvider"
        static let download = "planDownloadMbps"
        static let upload = "planUploadMbps"
    }

    /// Nil until the user has entered at least an advertised download speed.
    static func load(from defaults: UserDefaults = .standard) -> InternetPlan? {
        let download = defaults.double(forKey: Key.download)
        guard download > 0 else { return nil }
        return InternetPlan(
            provider: defaults.string(forKey: Key.provider) ?? "",
            downloadMbps: download,
            uploadMbps: defaults.double(forKey: Key.upload)
        )
    }
}

/// How a set of speed test results measures up against an `InternetPlan`.
struct PlanComparison {
    /// Share of the advertised speed reached by a test to count as "meets plan".
    static let meetsThreshold = 0.8
    /// Below this share a test counts as "far below plan".
    static let farBelowThreshold = 0.5

    let plan: InternetPlan
    let testCount: Int
    /// Average download as a fraction of the advertised download (1 = 100 %).
    let averageDownloadRatio: Double
    /// Nil when the plan has no advertised upload speed.
    let averageUploadRatio: Double?
    let medianDownloadMbps: Double
    let minimumDownloadMbps: Double
    let averagePing: Double
    /// Fraction of tests whose download reached `meetsThreshold` of the plan.
    let meetsPlanShare: Double
    /// Fraction of tests whose download was under `farBelowThreshold` of the plan.
    let farBelowShare: Double

    init?(plan: InternetPlan, results: [SpeedTestResult]) {
        guard !results.isEmpty, plan.downloadMbps > 0 else { return nil }

        let downloads = results.map { $0.score.downloadMbps }
        let uploads = results.map { $0.score.uploadMbps }
        let count = Double(results.count)

        self.plan = plan
        testCount = results.count
        averageDownloadRatio = downloads.reduce(0, +) / count / plan.downloadMbps
        averageUploadRatio = plan.uploadMbps > 0 ? uploads.reduce(0, +) / count / plan.uploadMbps : nil
        medianDownloadMbps = downloads.sorted()[downloads.count / 2]
        minimumDownloadMbps = downloads.min() ?? 0
        averagePing = results.reduce(0) { $0 + $1.ping } / count
        meetsPlanShare = Double(downloads.filter { $0 >= plan.downloadMbps * Self.meetsThreshold }.count) / count
        farBelowShare = Double(downloads.filter { $0 < plan.downloadMbps * Self.farBelowThreshold }.count) / count
    }

    /// Download of a single result as a fraction of the plan.
    func downloadRatio(of result: SpeedTestResult) -> Double {
        result.score.downloadMbps / plan.downloadMbps
    }
}
