//
//  CoverageMapView.swift
//  rinetworkspeed
//
//  Personal coverage map: cellular speed tests placed where they were run,
//  coloured by download speed and labelled with the radio technology.
//

import SwiftUI
import MapKit

nonisolated enum CoverageLevel: Equatable, Sendable {
    case fast, usable, slow

    /// 50 Mbps and more fast, 10 usable, below that slow.
    init(downloadMbps: Double) {
        switch downloadMbps {
        case 50...: self = .fast
        case 10..<50: self = .usable
        default: self = .slow
        }
    }
}

struct CoverageMapView: View {
    let results: [SpeedTestResult]

    @State private var technology = "all"

    private var located: [SpeedTestResult] {
        results.filter { $0.latitude != nil && $0.longitude != nil && (technology == "all" || $0.radioTechnology == technology) }
    }

    private var technologies: [String] {
        Array(Set(results.compactMap(\.radioTechnology))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            Map {
                ForEach(located) { result in
                    if let latitude = result.latitude, let longitude = result.longitude {
                        let mbps = result.downloadSpeed * 8 / 1_000_000
                        Annotation(result.radioTechnology ?? "", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                            Text(verbatim: mbps.fixed(0))
                                .appFont(size: 12, weight: .bold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(color(CoverageLevel(downloadMbps: mbps)), in: Capsule())
                                .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                                .accessibilityLabel(Text("\(mbps.fixed(0)) Mbps"))
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))

            VStack(alignment: .leading, spacing: 10) {
                if technologies.count > 1 {
                    Picker("Technology", selection: $technology) {
                        Text("All").tag("all")
                        ForEach(technologies, id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                HStack(spacing: 14) {
                    legend(.fast, "50+ Mbps")
                    legend(.usable, "10–50 Mbps")
                    legend(.slow, "< 10 Mbps")
                }
                Text("Cellular tests run with location access, rounded to about 100 m. Locations stay on this iPhone.")
                    .appFont(size: 12, weight: .regular, design: .rounded)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(AppTheme.pagePadding)
            .background(AppTheme.background)
        }
        .navigationTitle("Coverage Map")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legend(_ level: CoverageLevel, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color(level)).frame(width: 10, height: 10)
            Text(verbatim: text)
        }
        .appFont(size: 12, weight: .medium, design: .rounded)
        .foregroundStyle(AppTheme.secondaryText)
    }

    private func color(_ level: CoverageLevel) -> Color {
        switch level {
        case .fast: return AppTheme.ping
        case .usable: return AppTheme.warning
        case .slow: return AppTheme.danger
        }
    }
}
