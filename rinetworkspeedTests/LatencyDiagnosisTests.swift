//
//  LatencyDiagnosisTests.swift
//  rinetworkspeedTests
//
//  Statistics of a probe series and the "Wi-Fi or provider?" decision.
//

import Testing
@testable import rinetworkspeed

struct LatencyStatsTests {

    @Test func countsLostProbesAndIgnoresThemInAverages() {
        let stats = LatencyStats(samples: [10, -1, 20, 30, -1])
        #expect(stats.sent == 5)
        #expect(stats.lost == 2)
        #expect(stats.average == 20)
        #expect(stats.minimum == 10)
        #expect(stats.maximum == 30)
        #expect(stats.jitter == 10)
        #expect(stats.lossShare == 0.4)
    }

    @Test func emptyAndAllLost() {
        let empty = LatencyStats(samples: [])
        #expect(empty.sent == 0)
        #expect(empty.lossShare == 0)
        #expect(empty.average == 0)

        let lost = LatencyStats(samples: [-1, -1])
        #expect(lost.lossShare == 1)
        #expect(lost.average == 0)
        #expect(lost.jitter == 0)
    }
}

struct LatencyDiagnosisTests {
    /// `count` probes alternating between `value - spread / 2` and `value + spread / 2`
    /// (jitter equals `spread`), with `lost` of them lost.
    private func series(_ value: Double, spread: Double = 0, count: Int = 20, lost: Int = 0) -> LatencyStats {
        var samples = (0..<count).map { $0.isMultiple(of: 2) ? value - spread / 2 : value + spread / 2 }
        for i in 0..<lost { samples[i] = -1 }
        return LatencyStats(samples: samples)
    }

    @Test func silentRouter() {
        #expect(LatencyDiagnosis.evaluate(router: nil, internet: series(20)) == .routerSilent)
    }

    @Test func waitsForEnoughSamples() {
        #expect(LatencyDiagnosis.evaluate(router: series(3, count: 9), internet: series(20)) == .collecting)
        #expect(LatencyDiagnosis.evaluate(router: series(3), internet: series(20, count: 9)) == .collecting)
        #expect(LatencyDiagnosis.evaluate(router: series(3, count: 5), internet: series(20, count: 5), minimumSamples: 5) == .healthy)
    }

    @Test func healthyNetwork() {
        #expect(LatencyDiagnosis.evaluate(router: series(3, spread: 2), internet: series(25, spread: 5)) == .healthy)
    }

    @Test func slowOrUnevenRouterIsWiFi() {
        #expect(LatencyDiagnosis.evaluate(router: series(45), internet: series(70)) == .wifi)
        #expect(LatencyDiagnosis.evaluate(router: series(10, spread: 25), internet: series(30)) == .wifi)
        // 1 of 20 lost is 5 %, above the 3 % limit.
        #expect(LatencyDiagnosis.evaluate(router: series(3, lost: 1), internet: series(25)) == .wifi)
        #expect(LatencyDiagnosis.evaluate(router: series(3, lost: 20), internet: series(25)) == .wifi)
    }

    @Test func wifiWinsWhenBothAreBad() {
        #expect(LatencyDiagnosis.evaluate(router: series(50), internet: series(400, spread: 60, lost: 5)) == .wifi)
    }

    @Test func steadyRouterWithBadInternetIsBeyondRouter() {
        #expect(LatencyDiagnosis.evaluate(router: series(3), internet: series(40, lost: 2)) == .beyondRouter)
        #expect(LatencyDiagnosis.evaluate(router: series(3), internet: series(40, spread: 45)) == .beyondRouter)
        // The path beyond the router adds more than 150 ms.
        #expect(LatencyDiagnosis.evaluate(router: series(3), internet: series(160)) == .beyondRouter)
        #expect(LatencyDiagnosis.evaluate(router: series(3), internet: series(-1)) == .beyondRouter)
    }

    @Test func limitsAreExclusive() {
        // Exactly at the router limits still counts as fine.
        #expect(LatencyDiagnosis.evaluate(router: series(30, spread: 20), internet: series(60)) == .healthy)
        // Exactly 150 ms added still counts as fine.
        #expect(LatencyDiagnosis.evaluate(router: series(10), internet: series(160)) == .healthy)
    }
}
