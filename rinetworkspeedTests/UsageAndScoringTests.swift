//
//  UsageAndScoringTests.swift
//  rinetworkspeedTests
//
//  Data usage counter deltas, billing periods, speed test scoring, plan
//  comparison and the review prompt policy.
//

import Foundation
import Testing
@testable import rinetworkspeed

@MainActor
struct UsageDeltaTests {
    private func counters(boot: TimeInterval = 1_000, wifiIn: UInt32, wifiOut: UInt32 = 0, cellIn: UInt32 = 0, cellOut: UInt32 = 0) -> DataUsageMonitor.RawCounters {
        DataUsageMonitor.RawCounters(bootTime: boot, wifiIn: wifiIn, wifiOut: wifiOut, cellularIn: cellIn, cellularOut: cellOut)
    }

    @Test func firstSampleCountsNothing() {
        let delta = DataUsageMonitor.usageDelta(from: nil, to: counters(wifiIn: 5_000_000))
        #expect(delta.wifi == 0)
        #expect(delta.cellular == 0)
    }

    @Test func normalGrowthSumsInAndOut() {
        let last = counters(wifiIn: 1_000, wifiOut: 500, cellIn: 200, cellOut: 100)
        let now = counters(wifiIn: 3_000, wifiOut: 800, cellIn: 700, cellOut: 150)
        let delta = DataUsageMonitor.usageDelta(from: last, to: now)
        #expect(delta.wifi == 2_300)
        #expect(delta.cellular == 550)
    }

    @Test func thirtyTwoBitWrapIsHandled() {
        // Counter was 1 000 bytes below the 4 GiB limit and wrapped to 500.
        let last = counters(wifiIn: UInt32.max - 999)
        let now = counters(wifiIn: 500)
        let delta = DataUsageMonitor.usageDelta(from: last, to: now)
        #expect(delta.wifi == 1_500)
    }

    @Test func rebootUsesCurrentCountersAsDelta() {
        let last = counters(boot: 1_000, wifiIn: 9_000_000, cellIn: 4_000)
        let now = counters(boot: 50_000, wifiIn: 2_000, wifiOut: 1_000, cellIn: 300)
        let delta = DataUsageMonitor.usageDelta(from: last, to: now)
        #expect(delta.wifi == 3_000)
        #expect(delta.cellular == 300)
    }

    @Test func sameBootWithinRoundingIsNotAReboot() {
        let last = counters(boot: 1_000.2, wifiIn: 100)
        let now = counters(boot: 1_000.7, wifiIn: 400)
        #expect(DataUsageMonitor.usageDelta(from: last, to: now).wifi == 300)
    }
}

@MainActor
struct BillingPeriodTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func day(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: date)
    }

    @Test func onOrAfterResetDayStartsThisMonth() {
        let monitor = DataUsageMonitor()
        let start = monitor.billingPeriodStart(resetDay: 15, for: date(2026, 11, 20))
        #expect(day(start) == DateComponents(year: 2026, month: 11, day: 15))

        let onDay = monitor.billingPeriodStart(resetDay: 15, for: date(2026, 11, 15))
        #expect(day(onDay) == DateComponents(year: 2026, month: 11, day: 15))
    }

    @Test func beforeResetDayStartsLastMonth() {
        let monitor = DataUsageMonitor()
        let start = monitor.billingPeriodStart(resetDay: 15, for: date(2026, 11, 3))
        #expect(day(start) == DateComponents(year: 2026, month: 10, day: 15))
    }

    @Test func januaryRollsBackToDecember() {
        let monitor = DataUsageMonitor()
        let start = monitor.billingPeriodStart(resetDay: 20, for: date(2027, 1, 5))
        #expect(day(start) == DateComponents(year: 2026, month: 12, day: 20))
    }
}

@MainActor
struct SpeedTestScoreTests {
    /// Builds a score from megabits per second.
    private func score(down: Double, up: Double, ping: Double, jitter: Double? = nil) -> SpeedTestScore {
        SpeedTestScore(
            downloadBytesPerSecond: down * 1_000_000 / 8,
            uploadBytesPerSecond: up * 1_000_000 / 8,
            ping: ping,
            jitter: jitter
        )
    }

    @Test func convertsBytesPerSecondToMbps() {
        let s = score(down: 100, up: 20, ping: 10)
        #expect(abs(s.downloadMbps - 100) < 0.0001)
        #expect(abs(s.uploadMbps - 20) < 0.0001)
    }

    @Test func excellentConnectionGetsFullScore() {
        let s = score(down: 500, up: 100, ping: 10)
        #expect(s.value == 100)
        #expect(s.grade == "A")
    }

    @Test func gradeBoundaries() {
        // 18 (ping < 50) + 40 (down > 100) + 20 (up > 25) = 78 → B
        #expect(score(down: 150, up: 30, ping: 40).grade == "B")
        // 18 + 28 + 12 = 58 → C
        #expect(score(down: 60, up: 15, ping: 40).grade == "C")
        // 8 + 16 + 12 = 36 → D
        #expect(score(down: 30, up: 15, ping: 80).grade == "D")
        #expect(score(down: 2, up: 1, ping: 300).grade == "F")
    }

    @Test func useCasesFollowThresholds() {
        let slow = score(down: 8, up: 2, ping: 120)
        let supported = Dictionary(uniqueKeysWithValues: slow.useCases.map { ($0.id, $0.isSupported) })
        #expect(supported["browsing"] == true)
        #expect(supported["hdStreaming"] == false)
        #expect(supported["videoCalls"] == false)
        #expect(supported["gaming"] == false)

        let fast = score(down: 300, up: 50, ping: 15, jitter: 3)
        let unsupported = fast.useCases.filter { !$0.isSupported }
        #expect(unsupported.isEmpty)
    }

    @Test func highJitterRulesOutGaming() {
        let s = score(down: 300, up: 50, ping: 15, jitter: 45)
        #expect(s.useCases.first { $0.id == "gaming" }?.isSupported == false)
    }
}

@MainActor
struct PlanComparisonTests {
    private func result(down: Double, up: Double = 50, ping: Double = 10) -> SpeedTestResult {
        SpeedTestResult(date: Date(), downloadSpeed: down * 1_000_000 / 8, uploadSpeed: up * 1_000_000 / 8, ping: ping)
    }

    @Test func comparesAgainstAdvertisedSpeeds() throws {
        let plan = InternetPlan(provider: "Test", downloadMbps: 100, uploadMbps: 50)
        let c = try #require(PlanComparison(plan: plan, results: [
            result(down: 90), result(down: 85), result(down: 40), result(down: 100)
        ]))
        #expect(c.testCount == 4)
        #expect(abs(c.averageDownloadRatio - 0.7875) < 0.0001)
        #expect(abs((c.averageUploadRatio ?? 0) - 1.0) < 0.0001)
        #expect(c.meetsPlanShare == 0.75)
        #expect(c.farBelowShare == 0.25)
        #expect(abs(c.minimumDownloadMbps - 40) < 0.0001)
    }

    @Test func noUploadRatioWithoutAdvertisedUpload() throws {
        let plan = InternetPlan(provider: "", downloadMbps: 100, uploadMbps: 0)
        let c = try #require(PlanComparison(plan: plan, results: [result(down: 50)]))
        #expect(c.averageUploadRatio == nil)
    }

    @Test func emptyResultsGiveNoComparison() {
        let plan = InternetPlan(provider: "", downloadMbps: 100, uploadMbps: 10)
        #expect(PlanComparison(plan: plan, results: []) == nil)
    }
}

struct ReviewPromptPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func waitsForEnoughTests() {
        let policy = ReviewPromptPolicy(successfulTests: 2, lastPromptDate: nil, lastPromptedVersion: nil)
        #expect(!policy.shouldPrompt(afterScore: 90, currentVersion: "1.0", now: now))
    }

    @Test func asksAfterAGoodResult() {
        let policy = ReviewPromptPolicy(successfulTests: 3, lastPromptDate: nil, lastPromptedVersion: nil)
        #expect(policy.shouldPrompt(afterScore: 80, currentVersion: "1.0", now: now))
        #expect(!policy.shouldPrompt(afterScore: 40, currentVersion: "1.0", now: now))
    }

    @Test func asksOncePerVersionAndNotTooOften() {
        let recent = ReviewPromptPolicy(
            successfulTests: 10,
            lastPromptDate: now.addingTimeInterval(-30 * 86_400),
            lastPromptedVersion: "1.0"
        )
        #expect(!recent.shouldPrompt(afterScore: 90, currentVersion: "1.0", now: now))
        // New version, but only 30 days later.
        #expect(!recent.shouldPrompt(afterScore: 90, currentVersion: "1.1", now: now))

        let longAgo = ReviewPromptPolicy(
            successfulTests: 10,
            lastPromptDate: now.addingTimeInterval(-200 * 86_400),
            lastPromptedVersion: "1.0"
        )
        #expect(longAgo.shouldPrompt(afterScore: 90, currentVersion: "1.1", now: now))
    }
}
