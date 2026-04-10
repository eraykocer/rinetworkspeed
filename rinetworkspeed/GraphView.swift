//
//  GraphView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Charts

private enum GraphRange: String, CaseIterable, Identifiable {
    case lastMinute
    case lastFiveMinutes
    case lastThirtyMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastMinute:
            return "60sn"
        case .lastFiveMinutes:
            return "5dk"
        case .lastThirtyMinutes:
            return "30dk"
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
        }
    }
}

private struct GraphStat: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let color: Color
}

struct GraphView: View {
    @ObservedObject var monitor: NetworkStatsMonitor
    @AppStorage("speedUnit") private var speedUnit: String = "bytes"
    @State private var selectedRange: GraphRange = .lastMinute
    @State private var selectedSample: SpeedSample?

    private let backgroundColor = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let downloadColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private let uploadColor = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    private var filteredHistory: [SpeedSample] {
        let cutoff = Date().addingTimeInterval(-selectedRange.duration)
        return monitor.history.filter { $0.timestamp >= cutoff }
    }

    private var chartDomain: ClosedRange<Date> {
        let end = filteredHistory.last?.timestamp ?? Date()
        let start = max(filteredHistory.first?.timestamp ?? end.addingTimeInterval(-selectedRange.duration), end.addingTimeInterval(-selectedRange.duration))
        return start...end
    }

    private var maxSpeed: Double {
        let peak = filteredHistory.reduce(0.0) { partialResult, sample in
            max(partialResult, sample.downloadSpeed, sample.uploadSpeed)
        }
        return max(1, peak * 1.15)
    }

    private var stats: [GraphStat] {
        let maxDownload = filteredHistory.map(\.downloadSpeed).max() ?? 0
        let maxUpload = filteredHistory.map(\.uploadSpeed).max() ?? 0
        let avgDownload = filteredHistory.isEmpty ? 0 : filteredHistory.map(\.downloadSpeed).reduce(0, +) / Double(filteredHistory.count)
        let avgUpload = filteredHistory.isEmpty ? 0 : filteredHistory.map(\.uploadSpeed).reduce(0, +) / Double(filteredHistory.count)

        let totalTransferBytes = zip(filteredHistory, filteredHistory.dropFirst()).reduce(0.0) { partialResult, pair in
            let interval = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
            let averageRate = ((pair.0.downloadSpeed + pair.0.uploadSpeed) + (pair.1.downloadSpeed + pair.1.uploadSpeed)) / 2
            return partialResult + (averageRate * interval)
        }

        return [
            GraphStat(title: "Maks Download", value: formatRate(maxDownload), icon: "arrow.down.circle.fill", color: downloadColor),
            GraphStat(title: "Maks Upload", value: formatRate(maxUpload), icon: "arrow.up.circle.fill", color: uploadColor),
            GraphStat(title: "Ortalama Download", value: formatRate(avgDownload), icon: "arrow.down.and.line.horizontal.and.arrow.up", color: downloadColor),
            GraphStat(title: "Ortalama Upload", value: formatRate(avgUpload), icon: "arrow.up.and.line.horizontal.and.arrow.down", color: uploadColor),
            GraphStat(title: "Toplam Transfer", value: formatTransfer(totalTransferBytes), icon: "chart.bar.fill", color: .white),
            GraphStat(title: "Aktif Sure", value: formatDuration(monitor.activeDuration()), icon: "timer", color: .white)
        ]
    }

    private var csvExport: String {
        let header = "timestamp,download,upload"
        let rows = monitor.history.map {
            "\($0.timestamp.ISO8601Format()),\($0.downloadSpeed),\($0.uploadSpeed)"
        }
        return ([header] + rows).joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    chartCard
                    statsGrid
                    ShareLink(item: csvExport, preview: SharePreview("NetworkHistory.csv")) {
                        HStack {
                            Image(systemName: "square.and.arrow.up.fill")
                            Text("CSV Olarak Disa Aktar")
                        }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    .graphCardStyle()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Grafik")
        }
        .background(backgroundColor.ignoresSafeArea())
        .animation(.easeInOut, value: selectedRange)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Hiz Gecmisi")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()
            }

            Picker("Zaman Araligi", selection: $selectedRange) {
                ForEach(GraphRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Chart(filteredHistory) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Download", sample.downloadSpeed)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    .linearGradient(
                        colors: [downloadColor.opacity(0.35), downloadColor.opacity(0.02)],
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
                        colors: [uploadColor.opacity(0.3), uploadColor.opacity(0.02)],
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

                if let selectedSample {
                    RuleMark(x: .value("Selected", selectedSample.timestamp))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXScale(domain: chartDomain)
            .chartYScale(domain: 0...maxSpeed)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.white.opacity(0.05))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(xAxisLabel(for: date))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.white.opacity(0.05))
                    AxisValueLabel {
                        if let speed = value.as(Double.self) {
                            Text(formatAxisRate(speed))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let frame = geometry[proxy.plotAreaFrame]
                                    let xPosition = value.location.x - frame.origin.x

                                    guard xPosition >= 0, xPosition <= proxy.plotAreaSize.width,
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
            .frame(height: 280)

            if let selectedSample {
                tooltip(for: selectedSample)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(18)
        .graphCardStyle(highlighted: true)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ], spacing: 14) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: stat.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(stat.color)
                        Text(stat.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.74))
                    }

                    Text(stat.value)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .graphCardStyle()
            }
        }
    }

    private func tooltip(for sample: SpeedSample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sample.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))

            Label(formatRate(sample.downloadSpeed), systemImage: "arrow.down.circle.fill")
                .foregroundStyle(downloadColor)

            Label(formatRate(sample.uploadSpeed), systemImage: "arrow.up.circle.fill")
                .foregroundStyle(uploadColor)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func nearestSample(to date: Date) -> SpeedSample? {
        filteredHistory.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
    }

    private func xAxisLabel(for date: Date) -> String {
        switch selectedRange {
        case .lastMinute:
            return date.formatted(.dateTime.minute().second())
        case .lastFiveMinutes:
            return date.formatted(.dateTime.minute())
        case .lastThirtyMinutes:
            return date.formatted(.dateTime.hour().minute())
        }
    }

    private func formatRate(_ bytesPerSecond: Double) -> String {
        monitor.formatSpeed(bytesPerSecond)
    }

    private func formatAxisRate(_ bytesPerSecond: Double) -> String {
        let baseValue = speedUnit == "bits" ? bytesPerSecond * 8 : bytesPerSecond
        let kbValue = baseValue / 1024
        let unitPrefix = speedUnit == "bits" ? "bps" : "B/s"

        if kbValue >= 1024 {
            let major = kbValue / 1024
            return String(format: "%.1f M%@", major, unitPrefix)
        }
        return String(format: "%.0f K%@", kbValue, unitPrefix)
    }

    private func formatTransfer(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)s \(remainingMinutes)dk"
        }
        return "\(minutes) dk"
    }
}

private struct GraphCardModifier: ViewModifier {
    let highlighted: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 6)
            .shadow(color: highlighted ? Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255).opacity(0.15) : .clear, radius: 20, x: 0, y: 10)
    }
}

private extension View {
    func graphCardStyle(highlighted: Bool = false) -> some View {
        modifier(GraphCardModifier(highlighted: highlighted))
    }
}

#Preview {
    GraphView(monitor: NetworkStatsMonitor())
}
