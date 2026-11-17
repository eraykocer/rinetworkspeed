//
//  PeakHourAnalysis.swift
//  rinetworkspeed
//
//  Speed by time of day: congestion at the provider usually shows as slower
//  evenings. Used by Test History and the ISP report.
//

import Foundation
import SwiftUI

nonisolated enum DayPart: Int, CaseIterable, Comparable, Sendable {
    case night      // 00–06
    case morning    // 06–12
    case afternoon  // 12–18
    case evening    // 18–24

    init(hour: Int) {
        switch hour {
        case 0..<6: self = .night
        case 6..<12: self = .morning
        case 12..<18: self = .afternoon
        default: self = .evening
        }
    }

    static func < (lhs: DayPart, rhs: DayPart) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated struct PeakHourAnalysis: Equatable, Sendable {
    nonisolated struct Part: Equatable, Sendable {
        let part: DayPart
        let count: Int
        /// Median download, Mbps.
        let medianMbps: Double
    }

    nonisolated struct Finding: Equatable, Sendable {
        let slowest: DayPart
        let fastest: DayPart
        /// How much slower the slowest part is (0.42 = 42 % slower).
        let drop: Double
        let slowestCount: Int
        let fastestCount: Int
    }

    /// A part needs this many tests to be compared.
    static let minimumTests = 3
    /// The slowest part must be this much slower to be reported.
    static let minimumDrop = 0.3

    let parts: [Part]

    init(samples: [(date: Date, downloadMbps: Double)], calendar: Calendar = .current) {
        var grouped: [DayPart: [Double]] = [:]
        for sample in samples {
            grouped[DayPart(hour: calendar.component(.hour, from: sample.date)), default: []].append(sample.downloadMbps)
        }
        parts = grouped.map { part, values in
            let sorted = values.sorted()
            let middle = sorted.count / 2
            let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
            return Part(part: part, count: values.count, medianMbps: median)
        }
        .sorted { $0.part < $1.part }
    }

    /// The slowest and fastest parts with enough tests, when the gap is large.
    var finding: Finding? {
        let comparable = parts.filter { $0.count >= Self.minimumTests }
        guard comparable.count >= 2,
              let slowest = comparable.min(by: { $0.medianMbps < $1.medianMbps }),
              let fastest = comparable.max(by: { $0.medianMbps < $1.medianMbps }),
              fastest.medianMbps > 0 else { return nil }
        let drop = 1 - slowest.medianMbps / fastest.medianMbps
        guard drop >= Self.minimumDrop else { return nil }
        return Finding(slowest: slowest.part, fastest: fastest.part, drop: drop,
                       slowestCount: slowest.count, fastestCount: fastest.count)
    }
}

extension DayPart {
    var title: LocalizedStringKey {
        switch self {
        case .night: return "Night"
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }

    /// For the PDF report.
    var name: String {
        switch self {
        case .night: return String(localized: "Night")
        case .morning: return String(localized: "Morning")
        case .afternoon: return String(localized: "Afternoon")
        case .evening: return String(localized: "Evening")
        }
    }
}
