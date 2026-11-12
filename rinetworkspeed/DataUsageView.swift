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

    private let wifiColor = AppTheme.download
    private let cellularColor = AppTheme.upload

    private var chartEntries: [UsageChartEntry] {
        monitor.usageForLast7Days().flatMap { sample in
            [
                UsageChartEntry(date: sample.date, type: "WiFi", bytes: sample.wifiBytes),
                UsageChartEntry(date: sample.date, type: "Cellular", bytes: sample.cellularBytes)
            ]
        }
    }

    var body: some View {
        AppSection("Data Usage") {
            HStack(spacing: 0) {
                usageTile(title: "Today WiFi", icon: "wifi", value: monitor.formatBytes(monitor.todayWifiBytes), color: wifiColor)
                AppMetricDivider()
                usageTile(
                    title: "Today Cellular",
                    icon: "antenna.radiowaves.left.and.right",
                    value: monitor.formatBytes(monitor.todayCellularBytes),
                    color: cellularColor
                )
            }
            .padding(.vertical, 14)

            AppRowDivider(leadingInset: 0)

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
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(AppTheme.separator)
                    AxisValueLabel {
                        if let bytes = value.as(UInt64.self) {
                            Text(axisLabel(for: bytes))
                        } else if let bytes = value.as(Double.self) {
                            Text(axisLabel(for: UInt64(max(0, bytes))))
                        }
                    }
                    .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .chartLegend(position: .top, alignment: .trailing)
            .chartLegend(.visible)
            .frame(height: 220)
            .padding(16)
        }
    }

    private func usageTile(title: LocalizedStringKey, icon: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
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

