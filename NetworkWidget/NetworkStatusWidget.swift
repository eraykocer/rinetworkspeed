//
//  NetworkStatusWidget.swift
//  NetworkWidget
//
//  Home Screen widget showing the last speed test and today's data usage.
//  iOS does not let widgets measure anything live, so the values are the ones
//  the app last wrote to the shared App Group (see WidgetSharedStore.swift in
//  the app target; the keys below must match it).
//

import SwiftUI
import WidgetKit

// MARK: - Shared data

struct WidgetSnapshot {
    struct SpeedTest {
        let date: Date
        /// Bytes per second.
        let download: Double
        let upload: Double
        /// Milliseconds.
        let ping: Double
    }

    struct Usage {
        let wifiBytes: Int
        let cellularBytes: Int
    }

    let lastTest: SpeedTest?
    /// Nil when the app has not recorded any usage today.
    let todayUsage: Usage?

    static let suiteName = "group.rinetworkspeedapp"

    static func load(now: Date = Date()) -> WidgetSnapshot {
        let defaults = UserDefaults(suiteName: suiteName)

        var lastTest: SpeedTest?
        if let defaults, defaults.double(forKey: "widgetLastTestDate") > 0 {
            lastTest = SpeedTest(
                date: Date(timeIntervalSince1970: defaults.double(forKey: "widgetLastTestDate")),
                download: defaults.double(forKey: "widgetLastTestDownload"),
                upload: defaults.double(forKey: "widgetLastTestUpload"),
                ping: defaults.double(forKey: "widgetLastTestPing")
            )
        }

        var todayUsage: Usage?
        if let defaults {
            let updatedAt = Date(timeIntervalSince1970: defaults.double(forKey: "widgetUsageUpdatedAt"))
            // Yesterday's counters must not be shown as today's.
            if Calendar.current.isDate(updatedAt, inSameDayAs: now) {
                todayUsage = Usage(
                    wifiBytes: defaults.integer(forKey: "intentTodayWifi"),
                    cellularBytes: defaults.integer(forKey: "intentTodayCellular")
                )
            }
        }

        return WidgetSnapshot(lastTest: lastTest, todayUsage: todayUsage)
    }

    static let preview = WidgetSnapshot(
        lastTest: SpeedTest(date: Date().addingTimeInterval(-1_800), download: 15_600_000, upload: 3_100_000, ping: 14),
        todayUsage: Usage(wifiBytes: 1_288_490_188, cellularBytes: 214_748_364)
    )
}

// MARK: - Timeline

struct NetworkStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct NetworkStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> NetworkStatusEntry {
        NetworkStatusEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (NetworkStatusEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.preview : WidgetSnapshot.load()
        completion(NetworkStatusEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetworkStatusEntry>) -> Void) {
        let now = Date()
        var entries = [NetworkStatusEntry(date: now, snapshot: .load(now: now))]

        // Add an entry at midnight so yesterday's usage disappears on time.
        if let midnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) {
            entries.append(NetworkStatusEntry(date: midnight, snapshot: .load(now: midnight)))
        }

        // The app reloads the timeline after each test and when it is backgrounded.
        completion(Timeline(entries: entries, policy: .never))
    }
}

// MARK: - Widget

struct NetworkStatusWidget: Widget {
    static let kind = "NetworkStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NetworkStatusProvider()) { entry in
            NetworkStatusWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.background }
                .widgetURL(URL(string: "rinetworkspeed://speedtest"))
        }
        .configurationDisplayName("Network Status")
        .description("Your last speed test and today's data usage. Tap to run a new test.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private enum WidgetPalette {
    // Mirrors AppTheme in the app target.
    static let background = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let download = Color(red: 0.16, green: 0.47, blue: 0.96)
    static let upload = Color(red: 0.98, green: 0.55, blue: 0.16)
    static let ping = Color(red: 0.13, green: 0.77, blue: 0.47)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)
}

struct NetworkStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NetworkStatusEntry

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                speedTestColumn
                Divider().overlay(Color.white.opacity(0.12))
                usageColumn
            }
        default:
            speedTestColumn
        }
    }

    // MARK: Speed test

    @ViewBuilder
    private var speedTestColumn: some View {
        if let test = entry.snapshot.lastTest {
            VStack(alignment: .leading, spacing: 6) {
                header(title: "Last Test", icon: "gauge.with.dots.needle.67percent")

                Text(test.date, style: .relative)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.tertiaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WidgetPalette.download)
                    Text(Self.mbps(test.download))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Mbps")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetPalette.secondaryText)
                }

                HStack(spacing: 10) {
                    metric(icon: "arrow.up", value: Self.mbps(test.upload), unit: "Mbps", color: WidgetPalette.upload)
                    metric(icon: "timer", value: String(format: "%.0f", test.ping), unit: "ms", color: WidgetPalette.ping)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header(title: "Speed Test", icon: "gauge.with.dots.needle.67percent")
                Spacer(minLength: 0)
                Text("No test yet")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Tap to run your first speed test.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Usage

    private var usageColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(title: "Today", icon: "arrow.up.arrow.down.circle.fill")

            Spacer(minLength: 0)

            if let usage = entry.snapshot.todayUsage {
                Text(Self.bytes(usage.wifiBytes + usage.cellularBytes))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                metric(icon: "wifi", value: Self.bytes(usage.wifiBytes), unit: nil, color: WidgetPalette.download)
                metric(icon: "antenna.radiowaves.left.and.right", value: Self.bytes(usage.cellularBytes), unit: nil, color: WidgetPalette.upload)
            } else {
                Text("Open the app to update usage.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Building blocks

    private func header(title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(WidgetPalette.secondaryText)
            .lineLimit(1)
    }

    private func metric(icon: String, value: String, unit: String?, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .foregroundStyle(WidgetPalette.tertiaryText)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .lineLimit(1)
    }

    /// Speed test values are bytes/second; network speeds are shown in megabits/second.
    private static func mbps(_ bytesPerSecond: Double) -> String {
        String(format: "%.1f", bytesPerSecond * 8 / 1_000_000)
    }

    private static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .binary)
    }
}

#Preview(as: .systemMedium) {
    NetworkStatusWidget()
} timeline: {
    NetworkStatusEntry(date: Date(), snapshot: .preview)
    NetworkStatusEntry(date: Date(), snapshot: WidgetSnapshot(lastTest: nil, todayUsage: nil))
}
