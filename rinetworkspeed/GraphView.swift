//
//  GraphView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

private enum GraphRange: String, CaseIterable, Identifiable {
    case lastMinute
    case lastFiveMinutes
    case lastThirtyMinutes
    case lastDay
    case lastWeek

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .lastMinute:
            return "60s"
        case .lastFiveMinutes:
            return "5m"
        case .lastThirtyMinutes:
            return "30m"
        case .lastDay:
            return "24h"
        case .lastWeek:
            return "7d"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .lastMinute:
            return 60
        case .lastFiveMinutes:
            return 5 * 60
        case .lastThirtyMinutes:
            return 30 * 60
        case .lastDay:
            return 24 * 3600
        case .lastWeek:
            return 7 * 24 * 3600
        }
    }

    /// Ranges longer than the in-memory history are read from `SpeedHistoryArchive`.
    var isArchived: Bool {
        self == .lastDay || self == .lastWeek
    }

    /// Width of one bar in the archived chart.
    var binSize: TimeInterval {
        self == .lastWeek ? 3 * 3600 : 30 * 60
    }
}

private struct GraphStat: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let value: String
    let icon: String
    let color: Color
}

struct GraphView: View {
    // Not observed here: the chart, stats and export subviews observe the
    // monitor themselves, so per-tick history updates only re-render them.
    let monitor: NetworkStatsMonitor
    @AppStorage("graphRange") private var selectedRange: GraphRange = .lastMinute

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    Picker("Time Range", selection: $selectedRange) {
                        ForEach(GraphRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            AppSectionHeader("Speed History")
                            Spacer()
                            HStack(spacing: 12) {
                                legendDot(color: AppTheme.download, label: "DL")
                                legendDot(color: AppTheme.upload, label: "UL")
                            }
                            .padding(.trailing, 4)
                        }

                        if selectedRange.isArchived {
                            ArchiveChartCard(monitor: monitor, range: selectedRange)
                        } else {
                            GraphChartCard(monitor: monitor, range: selectedRange)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionHeader("Statistics")
                        if selectedRange.isArchived {
                            ArchiveStatsGrid(monitor: monitor, range: selectedRange)
                        } else {
                            GraphStatsGrid(monitor: monitor, range: selectedRange)
                        }
                    }

                    GraphExportButton(monitor: monitor)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .appPageBackground()
            .navigationTitle("Graph")
        }
        .appPageBackground()
    }

    private func legendDot(color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .appFont(size: 11, weight: .semibold, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }
}

// MARK: - Chart Card

private struct GraphChartCard: View {
    @ObservedObject var monitor: NetworkStatsMonitor
    let range: GraphRange
    @AppStorage("speedUnit") private var speedUnit: String = "bytes"
    @State private var selectedSample: SpeedSample?

    private let downloadColor = AppTheme.download
    private let uploadColor = AppTheme.upload

    /// Maximum number of points drawn by the chart. The 30-minute range holds
    /// thousands of samples; drawing all of them (×4 marks) on every update
    /// made the tab stutter.
    private static let maxChartPoints = 240

    private var filteredHistory: ArraySlice<SpeedSample> {
        monitor.history.samples(since: Date().addingTimeInterval(-range.duration))
    }

    /// Down-sampled points for drawing; keeps the newest sample as the last point.
    private func chartSamples(from samples: ArraySlice<SpeedSample>) -> [SpeedSample] {
        guard samples.count > Self.maxChartPoints else { return Array(samples) }
        let step = Double(samples.count - 1) / Double(Self.maxChartPoints - 1)
        return (0..<Self.maxChartPoints).map { i in
            samples[samples.startIndex + Int((Double(i) * step).rounded())]
        }
    }

    private func chartDomain(for samples: ArraySlice<SpeedSample>) -> ClosedRange<Date> {
        let end = samples.last?.timestamp ?? Date()
        let start = max(samples.first?.timestamp ?? end.addingTimeInterval(-range.duration), end.addingTimeInterval(-range.duration))
        return start...end
    }

    private func maxSpeed(for samples: ArraySlice<SpeedSample>) -> Double {
        let peak = samples.reduce(0.0) { partialResult, sample in
            max(partialResult, sample.downloadSpeed, sample.uploadSpeed)
        }
        return max(1, peak * 1.15)
    }

    var body: some View {
        // Computed once per render and shared by the chart modifiers.
        let samples = filteredHistory

        VStack(alignment: .leading, spacing: 14) {
            Chart(chartSamples(from: samples)) { sample in
                // Explicit yStart/yEnd keeps the two areas from stacking on top
                // of each other; `series` keeps DL and UL points in separate marks.
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Download", sample.downloadSpeed),
                    series: .value("Series", "Download")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(downloadColor.opacity(0.15))

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Download", sample.downloadSpeed),
                    series: .value("Series", "Download")
                )
                // Monotone interpolation never overshoots the data, unlike catmullRom.
                .interpolationMethod(.monotone)
                .foregroundStyle(downloadColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                AreaMark(
                    x: .value("Time", sample.timestamp),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Upload", sample.uploadSpeed),
                    series: .value("Series", "Upload")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(uploadColor.opacity(0.15))

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Upload", sample.uploadSpeed),
                    series: .value("Series", "Upload")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(uploadColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                if let selectedSample {
                    RuleMark(x: .value("Selected", selectedSample.timestamp))
                        .foregroundStyle(AppTheme.ink.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXScale(domain: chartDomain(for: samples))
            .chartYScale(domain: 0...maxSpeed(for: samples))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(AppTheme.separator)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(verbatim: xAxisLabel(for: date))
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppTheme.tertiaryText)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(AppTheme.separator)
                    AxisValueLabel {
                        if let speed = value.as(Double.self) {
                            Text(verbatim: formatAxisRate(speed))
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppTheme.tertiaryText)
                }
            }
            .chartLegend(.hidden)
            .chartPlotStyle { plotArea in
                plotArea.clipped()
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let frame = geometry[plotFrame]
                                    let xPosition = value.location.x - frame.origin.x

                                    guard xPosition >= 0, xPosition <= proxy.plotSize.width,
                                          let date: Date = proxy.value(atX: xPosition) else {
                                        return
                                    }

                                    selectedSample = nearestSample(to: date)
                                }
                                .onEnded { _ in
                                    selectedSample = nil
                                }
                        )
                }
            }
            .frame(height: 260)

            if let selectedSample {
                tooltip(for: selectedSample)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .appCard()
    }

    private func tooltip(for sample: SpeedSample) -> some View {
        HStack(spacing: 14) {
            Text(sample.timestamp.formatted(date: .omitted, time: .shortened))
                .foregroundStyle(AppTheme.secondaryText)

            Spacer(minLength: 0)

            Label(monitor.formatSpeed(sample.downloadSpeed), systemImage: "arrow.down")
                .foregroundStyle(downloadColor)

            Label(monitor.formatSpeed(sample.uploadSpeed), systemImage: "arrow.up")
                .foregroundStyle(uploadColor)
        }
        .appFont(size: 13, weight: .semibold, design: .rounded)
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.ink.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        )
    }

    private func nearestSample(to date: Date) -> SpeedSample? {
        filteredHistory.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
    }

    private func xAxisLabel(for date: Date) -> String {
        switch range {
        case .lastMinute:
            return date.formatted(.dateTime.minute().second())
        case .lastFiveMinutes:
            return date.formatted(.dateTime.minute())
        case .lastThirtyMinutes, .lastDay, .lastWeek:
            return date.formatted(.dateTime.hour().minute())
        }
    }

    private func formatAxisRate(_ bytesPerSecond: Double) -> String {
        graphAxisRate(bytesPerSecond, speedUnit: speedUnit)
    }
}

/// Compact axis label such as "12.5 MB/s" or "800 Kbps".
private func graphAxisRate(_ bytesPerSecond: Double, speedUnit: String) -> String {
    let baseValue = speedUnit == "bits" ? bytesPerSecond * 8 : bytesPerSecond
    let kbValue = baseValue / 1024
    let unitPrefix = speedUnit == "bits" ? "bps" : "B/s"

    if kbValue >= 1024 {
        let major = kbValue / 1024
        return major.fixed(1) + " M" + unitPrefix
    }
    return kbValue.fixed(0) + " K" + unitPrefix
}

// MARK: - Archived Ranges (24 h, 7 days)

private struct ArchiveBin: Identifiable {
    let start: Date
    let end: Date
    let averageDownload: Double
    let averageUpload: Double
    let peakDownload: Double
    let peakUpload: Double
    let minutes: Int

    var id: Date { start }

    static func make(from buckets: [SpeedMinuteBucket], size: TimeInterval) -> [ArchiveBin] {
        let grouped = Dictionary(grouping: buckets) { bucket in
            (bucket.start.timeIntervalSince1970 / size).rounded(.down) * size
        }
        return grouped.map { key, items in
            let count = Double(items.count)
            return ArchiveBin(
                start: Date(timeIntervalSince1970: key),
                end: Date(timeIntervalSince1970: key + size),
                averageDownload: items.reduce(0) { $0 + $1.averageDownload } / count,
                averageUpload: items.reduce(0) { $0 + $1.averageUpload } / count,
                peakDownload: items.map(\.peakDownload).max() ?? 0,
                peakUpload: items.map(\.peakUpload).max() ?? 0,
                minutes: items.count
            )
        }
        .sorted { $0.start < $1.start }
    }
}

private struct ArchiveChartCard: View {
    /// Observed only so the chart refreshes as new minutes are recorded.
    @ObservedObject var monitor: NetworkStatsMonitor
    let range: GraphRange
    @AppStorage("speedUnit") private var speedUnit: String = "bytes"

    var body: some View {
        let now = Date()
        let start = now.addingTimeInterval(-range.duration)
        let bins = ArchiveBin.make(from: SpeedHistoryArchive.shared.buckets(since: start), size: range.binSize)
        let gap = range.binSize * 0.08

        VStack(alignment: .leading, spacing: 12) {
            if bins.isEmpty {
                AppEmptyState(icon: "chart.bar.xaxis", title: "No history for this period yet.")
                    .frame(height: 220)
            } else {
                Chart(bins) { bin in
                    // Download in the left half of the slot, upload in the right half.
                    BarMark(
                        xStart: .value("Start", bin.start.addingTimeInterval(gap)),
                        xEnd: .value("End", bin.start.addingTimeInterval(range.binSize / 2)),
                        y: .value("Download", bin.averageDownload)
                    )
                    .foregroundStyle(AppTheme.download)

                    BarMark(
                        xStart: .value("Start", bin.start.addingTimeInterval(range.binSize / 2)),
                        xEnd: .value("End", bin.end.addingTimeInterval(-gap)),
                        y: .value("Upload", bin.averageUpload)
                    )
                    .foregroundStyle(AppTheme.upload)
                }
                .chartXScale(domain: start...now)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(AppTheme.separator)
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(verbatim: range == .lastWeek
                                     ? date.formatted(.dateTime.weekday(.abbreviated))
                                     : date.formatted(.dateTime.hour()))
                            }
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(AppTheme.separator)
                        AxisValueLabel {
                            if let speed = value.as(Double.self) {
                                Text(verbatim: graphAxisRate(speed, speedUnit: speedUnit))
                            }
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
                .frame(height: 220)
                .accessibilityLabel(Text("Average download and upload speed"))
            }

            Text("Average speed while the app was open. iOS does not allow measuring in the background, so periods when the app was closed are empty.")
                .appFont(size: 12, weight: .regular, design: .rounded)
                .foregroundStyle(AppTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
    }
}

private struct ArchiveStatsGrid: View {
    @ObservedObject var monitor: NetworkStatsMonitor
    let range: GraphRange

    var body: some View {
        let buckets = SpeedHistoryArchive.shared.buckets(since: Date().addingTimeInterval(-range.duration))
        let count = Double(max(buckets.count, 1))
        let totalBytes = buckets.reduce(0.0) { $0 + ($1.averageDownload + $1.averageUpload) * 60 }

        let stats = [
            GraphStat(id: "maxDownload", title: "Max Download", value: monitor.formatSpeed(buckets.map(\.peakDownload).max() ?? 0), icon: "arrow.down.circle.fill", color: AppTheme.download),
            GraphStat(id: "maxUpload", title: "Max Upload", value: monitor.formatSpeed(buckets.map(\.peakUpload).max() ?? 0), icon: "arrow.up.circle.fill", color: AppTheme.upload),
            GraphStat(id: "avgDownload", title: "Avg Download", value: monitor.formatSpeed(buckets.reduce(0) { $0 + $1.averageDownload } / count), icon: "arrow.down.and.line.horizontal.and.arrow.up", color: AppTheme.download),
            GraphStat(id: "avgUpload", title: "Avg Upload", value: monitor.formatSpeed(buckets.reduce(0) { $0 + $1.averageUpload } / count), icon: "arrow.up.and.line.horizontal.and.arrow.down", color: AppTheme.upload),
            GraphStat(id: "totalTransfer", title: "Total Transfer", value: ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .binary), icon: "chart.bar.fill", color: AppTheme.accent),
            GraphStat(id: "monitored", title: "Time Recorded", value: Duration.seconds(buckets.count * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)), icon: "timer", color: AppTheme.ping)
        ]

        GraphStatsCards(stats: stats)
    }
}

// MARK: - Stats Grid

private struct GraphStatsGrid: View {
    @ObservedObject var monitor: NetworkStatsMonitor
    let range: GraphRange

    private func stats(for samples: ArraySlice<SpeedSample>) -> [GraphStat] {
        // Single pass over the visible samples.
        var maxDownload = 0.0
        var maxUpload = 0.0
        var sumDownload = 0.0
        var sumUpload = 0.0
        var totalTransferBytes = 0.0
        var previous: SpeedSample?

        for sample in samples {
            maxDownload = max(maxDownload, sample.downloadSpeed)
            maxUpload = max(maxUpload, sample.uploadSpeed)
            sumDownload += sample.downloadSpeed
            sumUpload += sample.uploadSpeed
            if let previous {
                let interval = sample.timestamp.timeIntervalSince(previous.timestamp)
                let averageRate = ((previous.downloadSpeed + previous.uploadSpeed) + (sample.downloadSpeed + sample.uploadSpeed)) / 2
                totalTransferBytes += averageRate * interval
            }
            previous = sample
        }

        let count = Double(max(samples.count, 1))
        let avgDownload = sumDownload / count
        let avgUpload = sumUpload / count

        return [
            GraphStat(id: "maxDownload", title: "Max Download", value: monitor.formatSpeed(maxDownload), icon: "arrow.down.circle.fill", color: AppTheme.download),
            GraphStat(id: "maxUpload", title: "Max Upload", value: monitor.formatSpeed(maxUpload), icon: "arrow.up.circle.fill", color: AppTheme.upload),
            GraphStat(id: "avgDownload", title: "Avg Download", value: monitor.formatSpeed(avgDownload), icon: "arrow.down.and.line.horizontal.and.arrow.up", color: AppTheme.download),
            GraphStat(id: "avgUpload", title: "Avg Upload", value: monitor.formatSpeed(avgUpload), icon: "arrow.up.and.line.horizontal.and.arrow.down", color: AppTheme.upload),
            GraphStat(id: "totalTransfer", title: "Total Transfer", value: formatTransfer(totalTransferBytes), icon: "chart.bar.fill", color: AppTheme.accent),
            GraphStat(id: "activeDuration", title: "Active Duration", value: formatDuration(monitor.activeDuration()), icon: "timer", color: AppTheme.ping)
        ]
    }

    var body: some View {
        let samples = monitor.history.samples(since: Date().addingTimeInterval(-range.duration))
        GraphStatsCards(stats: stats(for: samples))
    }

    private static let transferFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.isAdaptive = true
        return formatter
    }()

    private func formatTransfer(_ bytes: Double) -> String {
        Self.transferFormatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// Two-column grid of statistic cards.
private struct GraphStatsCards: View {
    let stats: [GraphStat]

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        AppIconTile(systemName: stat.icon, tint: stat.color, size: 30)
                        Text(stat.title)
                            .appFont(size: 13, weight: .semibold, design: .rounded)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }

                    Text(stat.value)
                        .appFont(size: 21, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.primaryText)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .appCard()
            }
        }
    }
}

// MARK: - Export

/// Observes the monitor so the shared CSV always reflects the latest history.
private struct GraphExportButton: View {
    @ObservedObject var monitor: NetworkStatsMonitor

    var body: some View {
        ShareLink(item: HistoryCSVExport(history: monitor.history), preview: SharePreview("NetworkHistory.csv")) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Export as CSV")
            }
        }
        .buttonStyle(AppSecondaryButtonStyle())
    }
}

/// Builds the CSV only when the user actually shares it, instead of on every render.
private struct HistoryCSVExport: Transferable {
    let history: [SpeedSample]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            let header = "timestamp,download,upload"
            let rows = export.history.map {
                "\($0.timestamp.ISO8601Format()),\($0.downloadSpeed),\($0.uploadSpeed)"
            }
            return Data(([header] + rows).joined(separator: "\n").utf8)
        }
        .suggestedFileName("NetworkHistory.csv")
    }
}

#Preview {
    GraphView(monitor: NetworkStatsMonitor())
}
