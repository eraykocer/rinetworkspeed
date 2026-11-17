//
//  LatencyUnderLoadTests.swift
//  rinetworkspeedTests
//
//  Bufferbloat grade, its effect on the use cases, decoding of results saved
//  before latency under load existed, and the ISP report average.
//

import Foundation
import Testing
@testable import rinetworkspeed

@MainActor
struct LatencyUnderLoadTests {
    /// A fast connection, so only latency under load decides gaming and calls.
    private func score(ping: Double = 15, download: Double? = nil, upload: Double? = nil) -> SpeedTestScore {
        SpeedTestScore(
            downloadBytesPerSecond: 300 * 1_000_000 / 8,
            uploadBytesPerSecond: 50 * 1_000_000 / 8,
            ping: ping,
            jitter: 3,
            loadedLatencyDownload: download,
            loadedLatencyUpload: upload
        )
    }

    private func isSupported(_ id: String, in score: SpeedTestScore) -> Bool? {
        score.useCases.first { $0.id == id }?.isSupported
    }

    @Test func notMeasuredMeansNoGrade() {
        let s = score()
        #expect(s.latencyIncrease == nil)
        #expect(s.bufferbloatGrade == nil)
        #expect(s.bufferbloatSummary == nil)
        #expect(isSupported("gaming", in: s) == true)
    }

    @Test func usesTheWorseOfDownloadAndUpload() {
        let s = score(ping: 15, download: 40, upload: 115)
        #expect(s.latencyIncrease == 100)
        #expect(s.bufferbloatGrade == "C")
    }

    @Test func oneDirectionIsEnough() {
        #expect(score(ping: 15, download: 30).latencyIncrease == 15)
        #expect(score(ping: 15, upload: 30).latencyIncrease == 15)
    }

    @Test func loadedBelowIdleCountsAsNoIncrease() {
        let s = score(ping: 20, download: 18, upload: 19)
        #expect(s.latencyIncrease == 0)
        #expect(s.bufferbloatGrade == "A")
    }

    @Test(arguments: [
        (29.9, "A"), (30.0, "B"), (59.9, "B"), (60.0, "C"),
        (199.9, "C"), (200.0, "D"), (399.9, "D"), (400.0, "F"), (5_000.0, "F")
    ])
    func gradeBands(increase: Double, grade: String) {
        #expect(score(ping: 10, download: 10 + increase).bufferbloatGrade == grade)
    }

    @Test func bufferbloatRulesOutGamingBeforeCalls() {
        let moderate = score(ping: 15, download: 115) // +100 ms, grade C
        #expect(isSupported("gaming", in: moderate) == false)
        #expect(isSupported("videoCalls", in: moderate) == true)

        let severe = score(ping: 15, download: 515) // +500 ms, grade F
        #expect(isSupported("gaming", in: severe) == false)
        #expect(isSupported("videoCalls", in: severe) == false)

        let clean = score(ping: 15, download: 35) // +20 ms, grade A
        #expect(isSupported("gaming", in: clean) == true)
        #expect(isSupported("videoCalls", in: clean) == true)
    }

    @Test func resultsSavedBeforeTheFeatureStillDecode() throws {
        let json = """
        [{"id":"7D3F3C1E-8C55-4F35-9A47-2E3B7B8C9D10","date":700000000,
          "downloadSpeed":12500000,"uploadSpeed":2500000,"ping":18,"jitter":2}]
        """
        let results = try JSONDecoder().decode([SpeedTestResult].self, from: Data(json.utf8))
        #expect(results.first?.loadedLatencyDownload == nil)
        #expect(results.first?.score.bufferbloatGrade == nil)
    }

    @Test func newFieldsRoundTrip() throws {
        let result = SpeedTestResult(date: Date(timeIntervalSinceReferenceDate: 0),
                                     downloadSpeed: 1, uploadSpeed: 1, ping: 10,
                                     loadedLatencyDownload: 42, loadedLatencyUpload: 77)
        let decoded = try JSONDecoder().decode(SpeedTestResult.self, from: JSONEncoder().encode(result))
        #expect(decoded.loadedLatencyDownload == 42)
        #expect(decoded.loadedLatencyUpload == 77)
    }

    @Test func reportAveragesOnlyTestsThatMeasuredIt() throws {
        let plan = InternetPlan(provider: "", downloadMbps: 100, uploadMbps: 0)
        let results = [
            SpeedTestResult(date: Date(), downloadSpeed: 1, uploadSpeed: 1, ping: 10, loadedLatencyDownload: 50),
            SpeedTestResult(date: Date(), downloadSpeed: 1, uploadSpeed: 1, ping: 10, loadedLatencyDownload: 110),
            SpeedTestResult(date: Date(), downloadSpeed: 1, uploadSpeed: 1, ping: 10)
        ]
        let c = try #require(PlanComparison(plan: plan, results: results))
        #expect(c.latencyUnderLoadTestCount == 2)
        #expect(c.averageLatencyIncrease == 70)

        let old = try #require(PlanComparison(plan: plan, results: [results[2]]))
        #expect(old.averageLatencyIncrease == nil)
    }
}
