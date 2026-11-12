//
//  SpeedTestScoring.swift
//  rinetworkspeed
//
//  The single source for the 0–100 quality score, the letter grade and the
//  "what can this connection handle" summary. The result screen, history,
//  share card and PDF report all use it, so a test always gets the same grade.
//

import SwiftUI

struct SpeedTestScore {
    let downloadMbps: Double
    let uploadMbps: Double
    /// Milliseconds.
    let ping: Double
    /// Milliseconds; nil for results recorded before jitter was measured.
    let jitter: Double?

    /// Speed test values are stored in bytes per second.
    init(downloadBytesPerSecond: Double, uploadBytesPerSecond: Double, ping: Double, jitter: Double?) {
        self.downloadMbps = downloadBytesPerSecond * 8 / 1_000_000
        self.uploadMbps = uploadBytesPerSecond * 8 / 1_000_000
        self.ping = ping
        self.jitter = jitter
    }

    init(_ result: SpeedTestResult) {
        self.init(
            downloadBytesPerSecond: result.downloadSpeed,
            uploadBytesPerSecond: result.uploadSpeed,
            ping: result.ping,
            jitter: result.jitter
        )
    }

    // MARK: Score and grade

    /// Latency is worth 30 points, download 40 and upload 30.
    var value: Int {
        var score = 0

        if ping < 20 { score += 30 } else if ping < 50 { score += 18 } else if ping < 100 { score += 8 }

        if downloadMbps > 100 { score += 40 }
        else if downloadMbps > 50 { score += 28 }
        else if downloadMbps > 20 { score += 16 }
        else if downloadMbps > 5 { score += 8 }

        if uploadMbps > 50 { score += 30 }
        else if uploadMbps > 25 { score += 20 }
        else if uploadMbps > 10 { score += 12 }
        else if uploadMbps > 2 { score += 6 }

        return min(score, 100)
    }

    var grade: String {
        switch value {
        case 90...: return "A"
        case 75..<90: return "B"
        case 55..<75: return "C"
        case 35..<55: return "D"
        default: return "F"
        }
    }

    var gradeColor: Color {
        switch grade {
        case "A": return .green
        case "B": return Color(red: 132 / 255, green: 204 / 255, blue: 22 / 255)
        case "C": return .yellow
        case "D": return .orange
        default: return .red
        }
    }

    /// One-line verdict shown under the score.
    var verdict: LocalizedStringKey {
        switch value {
        case 90...: return "Excellent connection"
        case 75..<90: return "Very good connection"
        case 55..<75: return "Good connection"
        case 35..<55: return "Fair connection"
        default: return "Poor connection"
        }
    }

    // MARK: Use cases

    struct UseCase: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let icon: String
        let isSupported: Bool
    }

    /// Thresholds follow common streaming and conferencing service recommendations.
    var useCases: [UseCase] {
        let stableLatency = (jitter ?? 0) < 30
        return [
            UseCase(id: "browsing", title: "Browsing", icon: "safari", isSupported: downloadMbps >= 5),
            UseCase(id: "hdStreaming", title: "HD streaming", icon: "play.tv", isSupported: downloadMbps >= 10),
            UseCase(id: "4kStreaming", title: "4K streaming", icon: "4k.tv", isSupported: downloadMbps >= 25),
            UseCase(
                id: "videoCalls",
                title: "Video calls",
                icon: "video",
                isSupported: downloadMbps >= 4 && uploadMbps >= 4 && ping < 100
            ),
            UseCase(
                id: "gaming",
                title: "Online gaming",
                icon: "gamecontroller",
                isSupported: downloadMbps >= 5 && ping < 50 && stableLatency
            ),
            UseCase(id: "uploads", title: "Large uploads", icon: "icloud.and.arrow.up", isSupported: uploadMbps >= 20)
        ]
    }
}

extension SpeedTestResult {
    var score: SpeedTestScore { SpeedTestScore(self) }
}
