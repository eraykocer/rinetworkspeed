//
//  NetworkWidget.swift
//  NetworkWidget
//
//  Created by Eray Koçer on 9.04.2026.
//

import WidgetKit
import SwiftUI

struct NetworkEntry: TimelineEntry {
    let date: Date
    let downloadSpeed: Double
    let uploadSpeed: Double
}

struct NetworkTimelineProvider: TimelineProvider {
    private let suiteName = "com.eray.rinetworkspeed"

    func placeholder(in context: Context) -> NetworkEntry {
        NetworkEntry(date: .now, downloadSpeed: 12_500_000, uploadSpeed: 840_000)
    }

    func getSnapshot(in context: Context, completion: @escaping (NetworkEntry) -> Void) {
        completion(loadEntry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetworkEntry>) -> Void) {
        let now = Date()
        let entry = loadEntry(for: now)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)

        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    private func loadEntry(for date: Date) -> NetworkEntry {
        let defaults = UserDefaults(suiteName: suiteName)
        let downloadSpeed = defaults?.double(forKey: "downloadSpeed") ?? 0
        let uploadSpeed = defaults?.double(forKey: "uploadSpeed") ?? 0

        return NetworkEntry(date: date, downloadSpeed: downloadSpeed, uploadSpeed: uploadSpeed)
    }
}

struct NetworkWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NetworkTimelineProvider.Entry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if entry.downloadSpeed <= 0 && entry.uploadSpeed <= 0 {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: family == .systemSmall ? 22 : 26, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("No Data")
                        .font(.system(size: family == .systemSmall ? 16 : 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.86))
                }
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 10 : 12) {
                    speedRow(
                        title: "Download",
                        icon: "arrow.down",
                        color: .blue,
                        speed: entry.downloadSpeed
                    )

                    speedRow(
                        title: "Upload",
                        icon: "arrow.up",
                        color: .orange,
                        speed: entry.uploadSpeed
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(family == .systemSmall ? 12 : 16)
            }
        }
        .containerBackground(for: .widget) {
            Color.black
        }
    }

    private func speedRow(title: String, icon: String, color: Color, speed: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: family == .systemSmall ? 13 : 14, weight: .bold))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: family == .systemSmall ? 12 : 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            Spacer(minLength: 4)

            Text(speed > 0 ? formatSpeed(speed) : "No Data")
                .font(.system(size: family == .systemSmall ? 13 : 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec.isFinite, bytesPerSec > 0 else {
            return "No Data"
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

struct NetworkWidget: Widget {
    let kind: String = "NetworkWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NetworkTimelineProvider()) { entry in
            NetworkWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Network Speed")
        .description("Shows current download and upload speeds.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    NetworkWidget()
} timeline: {
    NetworkEntry(date: .now, downloadSpeed: 2_900_000, uploadSpeed: 430_000)
}

#Preview(as: .systemMedium) {
    NetworkWidget()
} timeline: {
    NetworkEntry(date: .now, downloadSpeed: 2_900_000, uploadSpeed: 430_000)
}
