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

    private let downloadColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private let uploadColor = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    private var now: Date { Date() }
    private var xStart: Date { now.addingTimeInterval(-60) }

    private var yMax: Double {
        let maxValue = monitor.history.reduce(0) { partialResult, sample in
            max(partialResult, sample.downloadSpeed, sample.uploadSpeed)
        }
        return max(1, maxValue * 1.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 60 Seconds")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            Chart(monitor.history) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Download", sample.downloadSpeed)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    .linearGradient(
                        colors: [downloadColor.opacity(0.4), downloadColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

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
                .foregroundStyle(
                    .linearGradient(
                        colors: [uploadColor.opacity(0.35), uploadColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

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
                    .foregroundStyle(.white.opacity(0.65))
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, yMax / 2, yMax]) { value in
                    AxisValueLabel {
                        if let speed = value.as(Double.self) {
                            Text(formatChartSpeed(speed))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.65))
                }
            }
            .chartPlotStyle { plot in
                plot
                    .background(Color.clear)
            }
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

    private func formatChartSpeed(_ bytesPerSecond: Double) -> String {
        let kbPerSecond = bytesPerSecond / 1024
        if kbPerSecond >= 1024 {
            return String(format: "%.1f MB/s", kbPerSecond / 1024)
        }
        return String(format: "%.0f KB/s", kbPerSecond)
    }
}

