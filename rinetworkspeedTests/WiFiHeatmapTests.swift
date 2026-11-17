//
//  WiFiHeatmapTests.swift
//  rinetworkspeedTests
//
//  Scores per metric, interpolation between spots, the mesh suggestion and
//  storage of a heatmap.
//

import Foundation
import Testing
@testable import rinetworkspeed

struct HeatmapMetricTests {

    @Test func routerScore() {
        let quick = HeatmapPoint(x: 0, y: 0, routerLatency: 3, routerJitter: 0)
        #expect(HeatmapMetric.router.score(quick, bestDownload: nil) == 1)

        let slow = HeatmapPoint(x: 0, y: 0, routerLatency: 60, routerJitter: 0)
        #expect(HeatmapMetric.router.score(slow, bestDownload: nil) == 0)

        // 10 ms with 5 ms jitter counts as 20 ms.
        let uneven = HeatmapPoint(x: 0, y: 0, routerLatency: 10, routerJitter: 5)
        let score = HeatmapMetric.router.score(uneven, bestDownload: nil) ?? -1
        #expect(abs(score - 40.0 / 57.0) < 0.0001)

        // 10 % loss alone adds 20 ms.
        let lossy = HeatmapPoint(x: 0, y: 0, routerLatency: 3, routerJitter: 0, routerLoss: 0.1)
        #expect(abs((HeatmapMetric.router.score(lossy, bestDownload: nil) ?? -1) - 37.0 / 57.0) < 0.0001)

        let silent = HeatmapPoint(x: 0, y: 0, routerLoss: 1)
        #expect(HeatmapMetric.router.score(silent, bestDownload: nil) == 0)
        #expect(HeatmapMetric.router.score(HeatmapPoint(x: 0, y: 0), bestDownload: nil) == nil)
    }

    @Test func downloadIsRelativeToTheBestSpot() {
        let point = HeatmapPoint(x: 0, y: 0, downloadMbps: 50)
        #expect(HeatmapMetric.download.score(point, bestDownload: 200) == 0.25)
        #expect(HeatmapMetric.download.score(point, bestDownload: nil) == nil)
        #expect(HeatmapMetric.download.score(HeatmapPoint(x: 0, y: 0), bestDownload: 200) == nil)
    }

    @Test func signalScore() {
        #expect(HeatmapMetric.signal.score(HeatmapPoint(x: 0, y: 0, rssi: -40), bestDownload: nil) == 1)
        #expect(HeatmapMetric.signal.score(HeatmapPoint(x: 0, y: 0, rssi: -85), bestDownload: nil) == 0)
        #expect(HeatmapMetric.signal.score(HeatmapPoint(x: 0, y: 0, rssi: -66), bestDownload: nil) == 0.4)
        #expect(HeatmapMetric.signal.score(HeatmapPoint(x: 0, y: 0), bestDownload: nil) == nil)
    }

    @Test func levels() {
        #expect(HeatmapLevel(score: 1) == .excellent)
        #expect(HeatmapLevel(score: 0.75) == .excellent)
        #expect(HeatmapLevel(score: 0.6) == .good)
        #expect(HeatmapLevel(score: 0.3) == .fair)
        #expect(HeatmapLevel(score: 0.1) == .weak)
    }
}

struct HeatmapMathTests {
    private let two: [(x: Double, y: Double, score: Double)] = [(0.2, 0.5, 1), (0.4, 0.5, 0)]

    @Test func exactSpotKeepsItsScore() {
        #expect(HeatmapMath.interpolate(x: 0.2, y: 0.5, samples: two, aspectRatio: 1) == 1)
    }

    @Test func halfwayIsTheAverage() throws {
        let value = try #require(HeatmapMath.interpolate(x: 0.3, y: 0.5, samples: two, aspectRatio: 1))
        #expect(abs(value - 0.5) < 0.0001)
    }

    @Test func closerSpotWeighsMore() throws {
        let value = try #require(HeatmapMath.interpolate(x: 0.25, y: 0.5, samples: two, aspectRatio: 1))
        #expect(value > 0.5)
    }

    @Test func farAwayStaysUncoloured() {
        #expect(HeatmapMath.interpolate(x: 0.95, y: 0.95, samples: two, aspectRatio: 1) == nil)
        #expect(HeatmapMath.interpolate(x: 0.5, y: 0.5, samples: [], aspectRatio: 1) == nil)
    }

    @Test func meshSuggestionIsHalfwayToTheWeakestSpot() throws {
        let samples: [(x: Double, y: Double, score: Double)] = [(0.1, 0.1, 0.9), (0.9, 0.9, 0.2), (0.5, 0.2, 0.6)]
        let spot = try #require(HeatmapMath.meshSuggestion(router: (0.1, 0.1), samples: samples))
        #expect(abs(spot.x - 0.5) < 0.0001)
        #expect(abs(spot.y - 0.5) < 0.0001)
    }

    @Test func noSuggestionWhenAllGoodOrNoRouter() {
        let good: [(x: Double, y: Double, score: Double)] = [(0.1, 0.1, 0.9), (0.9, 0.9, 0.6)]
        #expect(HeatmapMath.meshSuggestion(router: (0.1, 0.1), samples: good) == nil)
        let weak: [(x: Double, y: Double, score: Double)] = [(0.9, 0.9, 0.1)]
        #expect(HeatmapMath.meshSuggestion(router: nil, samples: weak) == nil)
    }
}

struct WiFiHeatmapSurveyTests {

    @Test func samplesSkipPointsWithoutTheValue() {
        var survey = WiFiHeatmapSurvey(name: "Home")
        survey.points = [
            HeatmapPoint(x: 0.1, y: 0.1, downloadMbps: 100),
            HeatmapPoint(x: 0.5, y: 0.5, downloadMbps: 50),
            HeatmapPoint(x: 0.9, y: 0.9)
        ]
        #expect(survey.bestDownload == 100)
        let samples = survey.samples(for: .download)
        #expect(samples.count == 2)
        #expect(samples.map(\.score) == [1, 0.5])
        #expect(survey.samples(for: .signal).isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        var survey = WiFiHeatmapSurvey(name: "Home")
        survey.routerX = 0.2
        survey.routerY = 0.3
        survey.points = [HeatmapPoint(x: 0.4, y: 0.6, routerLatency: 4, routerJitter: 1, downloadMbps: 80, rssi: -58)]
        let decoded = try JSONDecoder().decode(WiFiHeatmapSurvey.self, from: JSONEncoder().encode(survey))
        #expect(decoded == survey)
        #expect(decoded.router?.x == 0.2)
    }
}
