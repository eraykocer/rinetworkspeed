//
//  SpeedHistoryView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Charts

struct SpeedHistoryView: View {
    @ObservedObject var monitor: NetworkStatsMonitor

    private let downloadColor = AppTheme.download
    private let uploadColor = AppTheme.upload

    private var now: Date { Date() }
    private var xStart: Date { now.addingTimeInterval(-60) }

    private var yMax: Double {
        let maxValue = monitor.history.reduce(0) { partialResult, sample in
            max(partialResult, sample.downloadSpeed, sample.uploadSpeed)
        }
        return max(1, maxValue * 1.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AppIconTile(systemName: "waveform.path.ecg", tint: downloadColor, size: 32)
                Text("Last 60 Seconds")
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                Spacer(minLength: 8)
                legendDot(color: downloadColor, systemImage: "arrow.down")
                legendDot(color: uploadColor, systemImage: "arrow.up")
            }

            Chart(monitor.history) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Download", sample.downloadSpeed)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(downloadColor.opacity(0.15))

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Download", sample.downloadSpeed)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(downloadColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Upload", sample.uploadSpeed)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(uploadColor.opacity(0.15))

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Upload", sample.uploadSpeed)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(uploadColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            .chartXScale(domain: xStart...now)
            .chartYScale(domain: 0...yMax)
            .chartXAxis {
                AxisMarks(values: [xStart, now.addingTimeInterval(-30), now]) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            if abs(date.timeIntervalSince(now)) < 1 {
                                Text("Now")
                            } else {
                                Text("-\(Int(abs(date.timeIntervalSince(now))))s")
                            }
                        }
                    }
                    .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, yMax / 2, yMax]) { value in
                    AxisValueLabel {
                        if let speed = value.as(Double.self) {
                            Text(formatChartSpeed(speed))
                        }
                    }
                    .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .chartPlotStyle { plot in
                plot
                    .background(Color.clear)
            }
            .frame(height: 200)
        }
        .appCard(padding: 16)
    }

    /// Small colored capsule identifying a chart series.
    private func legendDot(color: Color, systemImage: String) -> some View {
        Image(systemName: systemImage)
            .appFont(size: 10, weight: .bold)
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .background(color.opacity(0.16), in: Circle())
    }

    private func formatChartSpeed(_ bytesPerSecond: Double) -> String {
        let kbPerSecond = bytesPerSecond / 1024
        if kbPerSecond >= 1024 {
            return (kbPerSecond / 1024).fixed(1) + " MB/s"
        }
        return kbPerSecond.fixed(0) + " KB/s"
    }
}

