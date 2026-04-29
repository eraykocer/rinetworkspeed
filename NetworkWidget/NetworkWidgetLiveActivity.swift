//
//  NetworkWidgetLiveActivity.swift
//  NetworkWidget
//
//  Created by Eray Koçer on 9.04.2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct NetworkSpeedAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var downloadSpeed: Double
        var uploadSpeed: Double
    }

    var title: String = "Network Speed"
}

struct NetworkSpeedLiveActivityView: View {
    let state: NetworkSpeedAttributes.ContentState

    var body: some View {
        HStack(spacing: 20) {
            speedMetric(
                title: "Download",
                icon: "arrow.down",
                color: .blue,
                speed: state.downloadSpeed
            )

            speedMetric(
                title: "Upload",
                icon: "arrow.up",
                color: .orange,
                speed: state.uploadSpeed
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func speedMetric(title: String, icon: String, color: Color, speed: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))

            Text(formatSpeed(speed))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec.isFinite, bytesPerSec > 0 else {
            return "0 B/s"
        }

        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var value = bytesPerSec
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f %@", value, units[unitIndex])
        }

        return String(format: "%.1f %@", value, units[unitIndex])
    }
}

struct NetworkWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NetworkSpeedAttributes.self) { context in
            NetworkSpeedLiveActivityView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedSpeed(
                        title: "Download",
                        icon: "arrow.down",
                        color: .blue,
                        speed: context.state.downloadSpeed
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedSpeed(
                        title: "Upload",
                        icon: "arrow.up",
                        color: .orange,
                        speed: context.state.uploadSpeed
                    )
                }
            } compactLeading: {
                compactSpeed(icon: "arrow.down", color: .blue, speed: context.state.downloadSpeed)
            } compactTrailing: {
                compactSpeed(icon: "arrow.up", color: .orange, speed: context.state.uploadSpeed)
            } minimal: {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.white)
            }
            .keylineTint(.white)
        }
    }

    private func compactSpeed(icon: String, color: Color, speed: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(shortFormatSpeed(speed))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
    }

    private func expandedSpeed(title: String, icon: String, color: Color, speed: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))

            Text(formatSpeed(speed))
                .foregroundStyle(.white)
                .monospacedDigit()
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func shortFormatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec.isFinite, bytesPerSec > 0 else {
            return "--"
        }

        let value = bytesPerSec / 1024
        if value >= 1024 {
            return String(format: "%.1fM", value / 1024)
        }

        return String(format: "%.0fK", value)
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec.isFinite, bytesPerSec > 0 else {
            return "0 B/s"
        }

        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var value = bytesPerSec
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f %@", value, units[unitIndex])
        }

        return String(format: "%.1f %@", value, units[unitIndex])
    }
}

#Preview("Notification", as: .content, using: NetworkSpeedAttributes()) {
    NetworkWidgetLiveActivity()
} contentStates: {
    NetworkSpeedAttributes.ContentState(downloadSpeed: 4_200_000, uploadSpeed: 950_000)
}
