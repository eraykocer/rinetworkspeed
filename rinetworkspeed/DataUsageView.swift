//
//  DataUsageView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Charts

private struct UsageChartEntry: Identifiable {
    let id = UUID()
    let date: Date
    let type: String
    let bytes: UInt64
}

struct DataUsageView: View {
    @ObservedObject var monitor: DataUsageMonitor

    private let wifiColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private let cellularColor = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    private var chartEntries: [UsageChartEntry] {
        monitor.usageForLast7Days().flatMap { sample in
            [
                UsageChartEntry(date: sample.date, type: "WiFi", bytes: sample.wifiBytes),
                UsageChartEntry(date: sample.date, type: "Cellular", bytes: sample.cellularBytes)
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Usage")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                usageTile(title: "Today WiFi", value: monitor.formatBytes(monitor.todayWifiBytes), color: wifiColor)
                usageTile(title: "Today Cellular", value: monitor.formatBytes(monitor.todayCellularBytes), color: cellularColor)
            }

            Chart(chartEntries) { entry in
                BarMark(
                    x: .value("Day", entry.date, unit: .day),
                    y: .value("Bytes", entry.bytes)
                )
                .position(by: .value("Type", entry.type))
                .foregroundStyle(by: .value("Type", entry.type))
                .cornerRadius(4)
            }
            .chartForegroundStyleScale([
                "WiFi": wifiColor,
                "Cellular": cellularColor
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let bytes = value.as(UInt64.self) {
                            Text(axisLabel(for: bytes))
                        } else if let bytes = value.as(Double.self) {
                            Text(axisLabel(for: UInt64(max(0, bytes))))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .chartLegend(position: .top, alignment: .trailing)
            .chartLegend(.visible)
            .frame(height: 220)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func usageTile(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.45), lineWidth: 1)
        )
    }

    private func axisLabel(for bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }
}

