//
//  NetworkStatusWidget.swift
//  NetworkWidget
//
//  Two widgets built on the same shared snapshot:
//   - Speed: last speed test (Home Screen, StandBy, Lock Screen).
//   - Data Usage: cellular usage against the monthly limit, or today's usage.
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

        var downloadMbps: Double { download * 8 / 1_000_000 }
        var uploadMbps: Double { upload * 8 / 1_000_000 }
    }

    struct Usage {
        let wifiBytes: Int
        let cellularBytes: Int
    }

    struct Period {
        let cellularBytes: Int
        let end: Date
        /// Nil when no data limit is set.
        let limitBytes: Double?

        var fraction: Double? {
            guard let limitBytes, limitBytes > 0 else { return nil }
            return min(Double(cellularBytes) / limitBytes, 1)
        }
    }

    let lastTest: SpeedTest?
    /// Nil when the app has not recorded any usage today.
    let todayUsage: Usage?
    /// Nil when the stored billing period has already ended.
    let period: Period?

    static let suiteName = "group.rinetworkspeedapp"

    static func load(now: Date = Date()) -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return WidgetSnapshot(lastTest: nil, todayUsage: nil, period: nil)
        }

        var lastTest: SpeedTest?
        if defaults.double(forKey: "widgetLastTestDate") > 0 {
            lastTest = SpeedTest(
                date: Date(timeIntervalSince1970: defaults.double(forKey: "widgetLastTestDate")),
                download: defaults.double(forKey: "widgetLastTestDownload"),
                upload: defaults.double(forKey: "widgetLastTestUpload"),
                ping: defaults.double(forKey: "widgetLastTestPing")
            )
        }

        var todayUsage: Usage?
        let updatedAt = Date(timeIntervalSince1970: defaults.double(forKey: "widgetUsageUpdatedAt"))
        // Yesterday's counters must not be shown as today's.
        if Calendar.current.isDate(updatedAt, inSameDayAs: now) {
            todayUsage = Usage(
                wifiBytes: defaults.integer(forKey: "intentTodayWifi"),
                cellularBytes: defaults.integer(forKey: "intentTodayCellular")
            )
        }

        var period: Period?
        let periodEnd = Date(timeIntervalSince1970: defaults.double(forKey: "widgetPeriodEnd"))
        if periodEnd > now {
            let limitGB = defaults.double(forKey: "widgetLimitGB")
            period = Period(
                cellularBytes: defaults.integer(forKey: "widgetPeriodCellular"),
                end: periodEnd,
                limitBytes: defaults.bool(forKey: "widgetLimitEnabled") && limitGB > 0 ? limitGB * 1_073_741_824 : nil
            )
        }

        return WidgetSnapshot(lastTest: lastTest, todayUsage: todayUsage, period: period)
    }

    static let preview = WidgetSnapshot(
        lastTest: SpeedTest(date: Date().addingTimeInterval(-1_800), download: 89_500_000, upload: 62_500_000, ping: 14),
        todayUsage: Usage(wifiBytes: 1_288_490_188, cellularBytes: 214_748_364),
        period: Period(cellularBytes: 3_758_096_384, end: Date().addingTimeInterval(9 * 86_400), limitBytes: 10 * 1_073_741_824)
    )

    static let empty = WidgetSnapshot(lastTest: nil, todayUsage: nil, period: nil)
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

        // The app reloads the timelines after each test and when it is backgrounded.
        completion(Timeline(entries: entries, policy: .never))
    }
}

// MARK: - Palette

enum WidgetPalette {
    // Mirrors AppTheme in the app target.
    static let background = Color(UIColor { traits in
        traits.userInterfaceStyle == .light
            ? UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
            : UIColor(red: 10 / 255, green: 10 / 255, blue: 10 / 255, alpha: 1)
    })
    static let download = Color(red: 0.16, green: 0.47, blue: 0.96)
    static let upload = Color(red: 0.98, green: 0.55, blue: 0.16)
    static let ping = Color(red: 0.13, green: 0.77, blue: 0.47)
    static let accent = Color(red: 0.42, green: 0.22, blue: 0.93)
    static let danger = Color(red: 0.99, green: 0.37, blue: 0.37)
}

enum WidgetFormat {
    static func mbps(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value >= 100 ? 0 : 1)).grouping(.never))
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .binary)
    }

    static let speedTestURL = URL(string: "rinetworkspeed://speedtest")
    static let usageURL = URL(string: "rinetworkspeed://usage")
}

// MARK: - Speed Widget

struct NetworkStatusWidget: Widget {
    static let kind = "NetworkStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NetworkStatusProvider()) { entry in
            SpeedWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.background }
                .widgetURL(WidgetFormat.speedTestURL)
        }
        .configurationDisplayName("Speed Test")
        .description("Your last speed test. Tap to run a new test.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SpeedWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NetworkStatusEntry

    private var test: WidgetSnapshot.SpeedTest? { entry.snapshot.lastTest }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                SpeedSummary(test: test)
                Divider()
                UsageSummary(snapshot: entry.snapshot)
            }
        default:
            SpeedSummary(test: test)
        }
    }

    // MARK: Lock Screen

    @ViewBuilder
    private var circular: some View {
        if let test {
            Gauge(value: min(test.downloadMbps, 1_000), in: 0...1_000) {
                Image(systemName: "arrow.down")
            } currentValueLabel: {
                Text(verbatim: WidgetFormat.mbps(test.downloadMbps))
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
            .accessibilityLabel(Text("Download \(WidgetFormat.mbps(test.downloadMbps)) Mbps"))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.title2)
            }
            .accessibilityLabel(Text("Speed Test"))
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let test {
            VStack(alignment: .leading, spacing: 2) {
                Label("Speed Test", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)
                    .widgetAccentable()
                Text(verbatim: "↓ \(WidgetFormat.mbps(test.downloadMbps))  ↑ \(WidgetFormat.mbps(test.uploadMbps)) Mbps")
                    .monospacedDigit()
                Text(test.date, style: .relative)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("Speed Test", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)
                    .widgetAccentable()
                Text("Tap to run your first speed test.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let test {
            Text(verbatim: "↓\(WidgetFormat.mbps(test.downloadMbps)) ↑\(WidgetFormat.mbps(test.uploadMbps)) Mbps")
        } else {
            Text("No test yet")
        }
    }
}

/// Last test block used by the small and medium Home Screen widgets.
private struct SpeedSummary: View {
    let test: WidgetSnapshot.SpeedTest?

    var body: some View {
        if let test {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Last Test", icon: "gauge.with.dots.needle.67percent")

                Text(test.date, style: .relative)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(WidgetPalette.download)
                    Text(verbatim: WidgetFormat.mbps(test.downloadMbps))
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Mbps")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    WidgetMetric(icon: "arrow.up", value: WidgetFormat.mbps(test.uploadMbps), unit: "Mbps", color: WidgetPalette.upload)
                    WidgetMetric(icon: "timer", value: test.ping.formatted(.number.precision(.fractionLength(0))), unit: "ms", color: WidgetPalette.ping)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: "Speed Test", icon: "gauge.with.dots.needle.67percent")
                Spacer(minLength: 0)
                Text("No test yet")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text("Tap to run your first speed test.")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Data Usage Widget

struct DataUsageWidget: Widget {
    static let kind = "DataUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NetworkStatusProvider()) { entry in
            DataUsageWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.background }
                .widgetURL(WidgetFormat.usageURL)
        }
        .configurationDisplayName("Data Usage")
        .description("Cellular usage against your monthly limit, or today's usage.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct DataUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NetworkStatusEntry

    private var period: WidgetSnapshot.Period? { entry.snapshot.period }

    var body: some View {
        switch family {
        case .accessoryCircular:
            if let period, let fraction = period.fraction {
                Gauge(value: fraction) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                } currentValueLabel: {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(verbatim: WidgetFormat.bytes(todayTotal))
                            .font(.system(size: 10, weight: .semibold))
                            .minimumScaleFactor(0.5)
                    }
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Data Usage", systemImage: "chart.pie.fill")
                    .font(.headline)
                    .widgetAccentable()
                if let period, let limit = period.limitBytes {
                    Text(verbatim: "\(WidgetFormat.bytes(period.cellularBytes)) / \(WidgetFormat.bytes(Int(limit)))")
                        .monospacedDigit()
                    Gauge(value: period.fraction ?? 0) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                } else {
                    Text("Today")
                        .foregroundStyle(.secondary)
                    Text(verbatim: WidgetFormat.bytes(todayTotal))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            UsageSummary(snapshot: entry.snapshot)
        }
    }

    private var todayTotal: Int {
        (entry.snapshot.todayUsage?.wifiBytes ?? 0) + (entry.snapshot.todayUsage?.cellularBytes ?? 0)
    }
}

/// Usage block: billing-period limit progress when a limit is set, otherwise today's usage.
private struct UsageSummary: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let period = snapshot.period, let limit = period.limitBytes, let fraction = period.fraction {
                WidgetHeader(title: "Cellular Limit", icon: "antenna.radiowaves.left.and.right")

                Spacer(minLength: 0)

                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(fraction >= 0.9 ? WidgetPalette.danger : .primary)

                ProgressView(value: fraction)
                    .tint(fraction >= 0.9 ? WidgetPalette.danger : WidgetPalette.upload)

                Text(verbatim: "\(WidgetFormat.bytes(period.cellularBytes)) / \(WidgetFormat.bytes(Int(limit)))")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                WidgetHeader(title: "Today", icon: "arrow.up.arrow.down.circle.fill")

                Spacer(minLength: 0)

                if let usage = snapshot.todayUsage {
                    Text(verbatim: WidgetFormat.bytes(usage.wifiBytes + usage.cellularBytes))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    WidgetMetric(icon: "wifi", value: WidgetFormat.bytes(usage.wifiBytes), unit: nil, color: WidgetPalette.download)
                    WidgetMetric(icon: "antenna.radiowaves.left.and.right", value: WidgetFormat.bytes(usage.cellularBytes), unit: nil, color: WidgetPalette.upload)
                } else {
                    Text("Open the app to update usage.")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Building blocks

private struct WidgetHeader: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct WidgetMetric: View {
    let icon: String
    let value: String
    let unit: LocalizedStringKey?
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(color)
            Text(verbatim: value)
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .lineLimit(1)
    }
}

// MARK: - Previews

#Preview(as: .systemMedium) {
    NetworkStatusWidget()
} timeline: {
    NetworkStatusEntry(date: Date(), snapshot: .preview)
    NetworkStatusEntry(date: Date(), snapshot: .empty)
}

#Preview(as: .accessoryRectangular) {
    DataUsageWidget()
} timeline: {
    NetworkStatusEntry(date: Date(), snapshot: .preview)
}
