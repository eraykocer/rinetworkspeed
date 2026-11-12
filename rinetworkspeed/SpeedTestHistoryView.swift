//
//  SpeedTestHistoryView.swift
//  rinetworkspeed
//
//  Full speed test history: trend chart, averages and filters by connection
//  type and time range. `SpeedTestHistoryRow` is also used on the speed test screen.
//

import SwiftUI
import Charts

// MARK: - Row

struct SpeedTestHistoryRow: View {
    let result: SpeedTestResult

    private var score: SpeedTestScore { result.score }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(score.grade)
                .appFont(size: 18, weight: .black, design: .rounded)
                .foregroundStyle(score.gradeColor)
                .frame(width: 40, height: 40)
                .background(score.gradeColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityLabel(Text("Grade \(score.grade)"))

            VStack(alignment: .leading, spacing: 5) {
                Text(result.date.formatted(date: .abbreviated, time: .shortened))
                    .appFont(size: 15, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)

                if let networkLine {
                    Label {
                        Text(verbatim: networkLine)
                    } icon: {
                        Image(systemName: (result.connection ?? .other).systemImage)
                    }
                    .appFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                }

                AppAdaptiveStack(spacing: 12) {
                    metric(icon: "arrow.down", value: Self.mbps(result.downloadSpeed), unit: "Mbps", color: AppTheme.download)
                    metric(icon: "arrow.up", value: Self.mbps(result.uploadSpeed), unit: "Mbps", color: AppTheme.upload)
                    metric(icon: "timer", value: result.ping.fixed(0), unit: "ms", color: AppTheme.ping)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Home Wi-Fi · Provider", or whatever part of it is known.
    private var networkLine: String? {
        var parts: [String] = []
        if let ssid = result.ssid {
            parts.append(ssid)
        } else if let kind = result.connection {
            parts.append(String(localized: kind.title))
        }
        if let isp = result.isp {
            parts.append(isp)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func metric(icon: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .appFont(size: 10, weight: .bold)
                .foregroundStyle(color)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(AppTheme.primaryText.opacity(0.85))
            Text(unit)
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .appFont(size: 12, weight: .semibold, design: .rounded)
        .lineLimit(1)
        .fixedSize()
    }

    static func mbps(_ bytesPerSecond: Double) -> String {
        (bytesPerSecond * 8 / 1_000_000).fixed(1)
    }
}

// MARK: - Full History Screen

struct SpeedTestHistoryView: View {
    @ObservedObject var manager: SpeedTestManager

    enum ConnectionFilter: String, CaseIterable, Identifiable {
        case all, wifi, cellular
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .all: return "All"
            case .wifi: return "Wi-Fi"
            case .cellular: return "Cellular"
            }
        }
    }

    enum RangeFilter: String, CaseIterable, Identifiable {
        case week, month, all
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .week: return "Last 7 Days"
            case .month: return "Last 30 Days"
            case .all: return "All Time"
            }
        }

        var startDate: Date? {
            switch self {
            case .week: return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .month: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
            case .all: return nil
            }
        }
    }

    @AppStorage("historyConnectionFilter") private var connectionFilter: ConnectionFilter = .all
    @AppStorage("historyRangeFilter") private var rangeFilter: RangeFilter = .month
    /// Wi-Fi name to show; empty means all networks.
    @AppStorage("historyNetworkFilter") private var networkFilter: String = ""
    @State private var showingClearConfirmation = false

    /// Wi-Fi names seen in the history, most recently tested first.
    private var networkNames: [String] {
        var seen = Set<String>()
        return manager.history.compactMap(\.ssid).filter { seen.insert($0).inserted }
    }

    private var filtered: [SpeedTestResult] {
        manager.history.filter { result in
            if let start = rangeFilter.startDate, result.date < start { return false }
            if !networkFilter.isEmpty, result.ssid != networkFilter { return false }
            switch connectionFilter {
            case .all: return true
            case .wifi: return result.connection == .wifi
            case .cellular: return result.connection == .cellular
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                filterBar

                if networkFilter.isEmpty && !networkNames.isEmpty {
                    networksSection
                }

                if filtered.isEmpty {
                    AppEmptyState(icon: "line.3.horizontal.decrease.circle", title: "No tests match these filters.")
                        .appCard(padding: nil)
                } else {
                    trendSection
                    averagesSection
                    planSection
                    listSection
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .appPageBackground()
        .navigationTitle("Test History")
        #if DEBUG
        .task {
            // Layout review helper: launch with `-debugWriteISPReport YES`.
            guard UserDefaults.standard.bool(forKey: "debugWriteISPReport"), let plan = InternetPlan.load() else { return }
            let url = URL.documentsDirectory.appending(path: "isp-report.pdf")
            try? ISPReportGenerator().makePDF(plan: plan, results: filtered).write(to: url)
        }
        #endif
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all speed test results?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { manager.clearHistory() }
        }
    }

    // MARK: Filters

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Connection", selection: $connectionFilter) {
                ForEach(ConnectionFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Picker("Time Range", selection: $rangeFilter) {
                ForEach(RangeFilter.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.menu)
            .tint(AppTheme.primaryText)

            if !networkNames.isEmpty {
                Picker("Network", selection: $networkFilter) {
                    Text("All Networks").tag("")
                    ForEach(networkNames, id: \.self) { name in
                        Text(verbatim: name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppTheme.primaryText)
            }
        }
        .onAppear {
            // A saved network that no longer has tests would hide everything.
            if !networkFilter.isEmpty && !networkNames.contains(networkFilter) {
                networkFilter = ""
            }
        }
    }

    // MARK: Networks

    /// One row per Wi-Fi network with its own averages, e.g. "Home" against "Office".
    private var networksSection: some View {
        AppSection("Networks", footer: "Wi-Fi names are recorded when location access is allowed. Tap a network to see only its tests.") {
            ForEach(networkNames, id: \.self) { name in
                let results = manager.history.filter { $0.ssid == name }
                let count = Double(results.count)
                let download = results.reduce(0) { $0 + $1.downloadSpeed } / count
                let ping = results.reduce(0) { $0 + $1.ping } / count

                Button {
                    networkFilter = name
                } label: {
                    AppRow(icon: "wifi", tint: AppTheme.download, verbatimTitle: name, subtitle: "\(results.count) tests") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: "↓ \(SpeedTestHistoryRow.mbps(download)) Mbps")
                                .appFont(size: 14, weight: .semibold, design: .rounded)
                                .foregroundStyle(AppTheme.primaryText)
                            Text(verbatim: "\(ping.fixed(0)) ms")
                                .appFont(size: 12, weight: .medium, design: .rounded)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .monospacedDigit()
                        AppChevron()
                    }
                }
                .buttonStyle(AppRowButtonStyle())

                if name != networkNames.last {
                    AppRowDivider()
                }
            }
        }
    }

    // MARK: Trend

    // Swift Charts shows series values verbatim in the legend, so they are localized here.
    private static let downloadSeries = String(localized: "Download")
    private static let uploadSeries = String(localized: "Upload")

    private struct TrendPoint: Identifiable {
        let id: String
        let date: Date
        let series: String
        let mbps: Double
    }

    private var trendPoints: [TrendPoint] {
        filtered.flatMap { result in
            [
                TrendPoint(id: "\(result.id)-d", date: result.date, series: Self.downloadSeries, mbps: result.downloadSpeed * 8 / 1_000_000),
                TrendPoint(id: "\(result.id)-u", date: result.date, series: Self.uploadSeries, mbps: result.uploadSpeed * 8 / 1_000_000)
            ]
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("Trend")

            Chart(trendPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Mbps", point.mbps)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Mbps", point.mbps)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .symbolSize(24)
            }
            .chartForegroundStyleScale([
                Self.downloadSeries: AppTheme.download,
                Self.uploadSeries: AppTheme.upload
            ])
            .chartYAxisLabel("Mbps")
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 200)
            .padding(16)
            .appCard(padding: nil)
        }
    }

    // MARK: Averages

    private var averagesSection: some View {
        let count = Double(filtered.count)
        let download = filtered.reduce(0) { $0 + $1.downloadSpeed } / count
        let upload = filtered.reduce(0) { $0 + $1.uploadSpeed } / count
        let ping = filtered.reduce(0) { $0 + $1.ping } / count

        return VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("Averages")

            HStack(spacing: 0) {
                AppMetric(icon: "arrow.down", value: SpeedTestHistoryRow.mbps(download), unit: "Mbps", tint: AppTheme.download, caption: "Download")
                AppMetricDivider()
                AppMetric(icon: "arrow.up", value: SpeedTestHistoryRow.mbps(upload), unit: "Mbps", tint: AppTheme.upload, caption: "Upload")
                AppMetricDivider()
                AppMetric(icon: "timer", value: ping.fixed(0), unit: "ms", tint: AppTheme.ping, caption: "Ping")
                AppMetricDivider()
                AppMetric(icon: nil, value: "\(filtered.count)", unit: "", caption: "Tests")
            }
            .padding(.vertical, 14)
            .appCard(padding: nil)
        }
    }

    // MARK: Plan Comparison

    @ViewBuilder
    private var planSection: some View {
        if let plan = InternetPlan.load(), let comparison = PlanComparison(plan: plan, results: filtered) {
            VStack(alignment: .leading, spacing: 10) {
                AppSectionHeader("Compared with Your Plan")

                VStack(spacing: 0) {
                    planRow(
                        title: "Average download",
                        value: comparison.averageDownloadRatio.formatted(.percent.precision(.fractionLength(0))),
                        isGood: comparison.averageDownloadRatio >= PlanComparison.meetsThreshold
                    )
                    if let upload = comparison.averageUploadRatio {
                        AppRowDivider(leadingInset: 16)
                        planRow(
                            title: "Average upload",
                            value: upload.formatted(.percent.precision(.fractionLength(0))),
                            isGood: upload >= PlanComparison.meetsThreshold
                        )
                    }
                    AppRowDivider(leadingInset: 16)
                    planRow(
                        title: "Tests reaching 80% of plan",
                        value: comparison.meetsPlanShare.formatted(.percent.precision(.fractionLength(0))),
                        isGood: comparison.meetsPlanShare >= 0.8
                    )

                    AppRowDivider(leadingInset: 0)

                    ShareLink(
                        item: ISPReportExport(plan: plan, results: filtered),
                        preview: SharePreview("Internet Speed Report")
                    ) {
                        Label("ISP Report (PDF)", systemImage: "doc.text.fill")
                            .appFont(size: 15, weight: .semibold, design: .rounded)
                            .foregroundStyle(AppTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(AppRowButtonStyle())
                }
                .appCard(padding: nil)

                Text("The report uses the tests shown with the current filters. Wi-Fi or wired tests reflect your home connection best.")
                    .appFont(size: 12, weight: .regular, design: .rounded)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .padding(.horizontal, 4)
            }
        } else if InternetPlan.load() == nil {
            AppSection(footer: "Add the speeds your provider advertises in Settings → Internet Plan to compare results and create an ISP report.") {
                AppRow(icon: "building.2.fill", tint: .teal, title: "Compare with Your Plan", subtitle: "Not set up")
            }
        }
    }

    private func planRow(title: LocalizedStringKey, value: String, isGood: Bool) -> some View {
        HStack {
            Text(title)
                .appFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .appFont(size: 15, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(isGood ? AppTheme.ping : AppTheme.danger)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: List

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("Results")

            VStack(spacing: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { result in
                        SpeedTestHistoryRow(result: result)
                            .contextMenu {
                                Button(role: .destructive) {
                                    manager.deleteHistory(ids: [result.id])
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                        if result.id != filtered.last?.id {
                            AppRowDivider()
                        }
                    }
                }

                AppRowDivider(leadingInset: 0)

                Button {
                    showingClearConfirmation = true
                } label: {
                    Text("Clear History")
                        .appFont(size: 15, weight: .semibold, design: .rounded)
                        .foregroundStyle(AppTheme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AppRowButtonStyle())
            }
            .appCard(padding: nil)
        }
    }
}

#Preview {
    NavigationStack {
        SpeedTestHistoryView(manager: SpeedTestManager())
    }
}
