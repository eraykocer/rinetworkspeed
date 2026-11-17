//
//  LatencyDiagnosis.swift
//  rinetworkspeed
//
//  Pings the router and an internet host side by side and tells whether a
//  problem is on the Wi-Fi (between this iPhone and the router) or beyond the
//  router (the provider or the path to the host). Used by the Ping Monitor and
//  the troubleshooter.
//

import Foundation

/// Summary of a series of probes. A negative sample is a lost probe.
nonisolated struct LatencyStats: Equatable, Sendable {
    let sent: Int
    let lost: Int
    /// Milliseconds over answered probes; 0 when none answered.
    let average: Double
    let minimum: Double
    let maximum: Double
    /// Mean absolute difference between consecutive answered probes.
    let jitter: Double

    init(samples: [Double]) {
        let answered = samples.filter { $0 >= 0 }
        sent = samples.count
        lost = samples.count - answered.count
        average = answered.isEmpty ? 0 : answered.reduce(0, +) / Double(answered.count)
        minimum = answered.min() ?? 0
        maximum = answered.max() ?? 0
        let deltas = zip(answered.dropFirst(), answered).map { abs($0 - $1) }
        jitter = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count)
    }

    /// Fraction of probes lost (0…1).
    var lossShare: Double {
        sent == 0 ? 0 : Double(lost) / Double(sent)
    }
}

nonisolated enum LatencyDiagnosis: Equatable, Sendable {
    /// Not enough probes yet.
    case collecting
    /// Both the router and the internet host answer steadily.
    case healthy
    /// The router itself answers late, unevenly or not at all: Wi-Fi problem.
    case wifi
    /// The router answers steadily, the internet host does not.
    case beyondRouter
    /// The router does not answer test connections, so the two cannot be separated.
    case routerSilent

    // These thresholds are heuristics. A router on a healthy Wi-Fi link
    // usually answers within a few milliseconds with little variation.

    /// A router slower than this on average points to the Wi-Fi link.
    static let routerAverageLimit: Double = 30
    static let routerJitterLimit: Double = 20
    /// Jitter towards the internet host, matching the speed test's gaming limit.
    static let internetJitterLimit: Double = 30
    /// Latency the path beyond the router may add before it counts as slow.
    static let addedLatencyLimit: Double = 150
    /// Losing this share of probes or more counts as a problem.
    static let lossLimit: Double = 0.03

    /// - Parameters:
    ///   - router: probes to the router; nil when the router did not answer
    ///     any test connection.
    ///   - internet: probes to the internet host over the same period.
    static func evaluate(router: LatencyStats?, internet: LatencyStats, minimumSamples: Int = 10) -> LatencyDiagnosis {
        guard let router else { return .routerSilent }
        guard router.sent >= minimumSamples, internet.sent >= minimumSamples else { return .collecting }

        let routerAnswered = router.sent - router.lost
        let routerUnstable = routerAnswered == 0
            || router.lossShare >= lossLimit
            || router.average > routerAverageLimit
            || router.jitter > routerJitterLimit
        if routerUnstable { return .wifi }

        let internetAnswered = internet.sent - internet.lost
        let internetUnstable = internetAnswered == 0
            || internet.lossShare >= lossLimit
            || internet.jitter > internetJitterLimit
            || internet.average - router.average > addedLatencyLimit
        return internetUnstable ? .beyondRouter : .healthy
    }
}
