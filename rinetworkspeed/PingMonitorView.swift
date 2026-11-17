//
//  PingMonitorView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Charts

private enum PingHostOption: String, CaseIterable, Identifiable {
    case cloudflare
    case google
    case custom

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .cloudflare:
            return "Cloudflare"
        case .google:
            return "Google"
        case .custom:
            return "Custom"
        }
    }

    var host: String {
        switch self {
        case .cloudflare:
            return "1.1.1.1"
        case .google:
            return "8.8.8.8"
        case .custom:
            return ""
        }
    }
}

// MARK: - Status Styling

private extension ConnectionStatus {
    var color: Color {
        switch self {
        case .excellent:
            return AppTheme.ping
        case .good:
            return Color(red: 134 / 255, green: 239 / 255, blue: 172 / 255)
        case .fair:
            return AppTheme.warning
        case .poor:
            return AppTheme.upload
        case .timeout:
            return AppTheme.danger
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .excellent:
            return "Excellent"
        case .good:
            return "Good"
        case .fair:
            return "Fair"
        case .poor:
            return "Poor"
        case .timeout:
            return "Timeout"
        }
    }

    /// Hero card color; shifts from green to red as latency degrades.
    var heroTint: Color {
        switch self {
        case .excellent, .good:
            return Color(red: 0.05, green: 0.52, blue: 0.62)
        case .fair:
            return Color(red: 0.80, green: 0.45, blue: 0.08)
        case .poor:
            return Color(red: 0.86, green: 0.27, blue: 0.20)
        case .timeout:
            return Color(red: 0.62, green: 0.12, blue: 0.22)
        }
    }
}

// MARK: - Main View

struct PingMonitorView: View {
    /// Not observed here: only the small live subviews observe the monitor, so the
    /// 1 s ping updates don't re-render the host selector.
    let monitor: PingMonitor
    @State private var selectedHost: PingHostOption = .cloudflare
    @State private var customHost: String = ""

    init(monitor: PingMonitor, initialHost: String = "") {
        self.monitor = monitor
        if !initialHost.isEmpty {
            _selectedHost = State(initialValue: .custom)
            _customHost   = State(initialValue: initialHost)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    PingHeroCard(monitor: monitor, hostText: activeHostText, onToggle: toggleRunning)

                    AppSection("Live Chart") {
                        PingLiveChart(monitor: monitor, hostText: activeHostText)
                            .padding(16)
                    }

                    PingSplitSection(monitor: monitor, hostText: activeHostText)

                    AppSection("Statistics") {
                        PingStatsRows(monitor: monitor)
                    }

                    hostSelectorSection
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .appPageBackground()
            .navigationTitle("Ping Monitor")
            .toolReport(monitor) { $0.reportText }
            .onAppear {
                startIfNeeded()
            }
            // Stop pinging once the screen is closed; otherwise the 1 s timer kept
            // running (and publishing) while the user browsed other tabs.
            .onDisappear {
                monitor.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                monitor.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                startIfNeeded()
            }
        }
        .appPageBackground()
    }

    private var hostSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("Host Selector")

            Picker("Host", selection: $selectedHost) {
                ForEach(PingHostOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)
            .appCard(padding: nil)
            .onChange(of: selectedHost) { _, newValue in
                applyHostChange(for: newValue)
            }

            if selectedHost == .custom {
                AppInputField(
                    icon: "server.rack",
                    placeholder: "Enter host",
                    text: $customHost,
                    showsFavorites: true,
                    onSubmit: applyCustomHost
                )
            }
        }
    }

    private var activeHostText: String {
        selectedHost == .custom ? customHost : selectedHost.host
    }

    private func toggleRunning() {
        if monitor.isRunning {
            monitor.stop()
        } else {
            startIfNeeded()
        }
    }

    private func startIfNeeded() {
        let host = selectedHost == .custom ? customHost : selectedHost.host
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        monitor.start(host: host)
    }

    private func applyHostChange(for option: PingHostOption) {
        monitor.stop()
        monitor.reset()

        if option != .custom {
            monitor.start(host: option.host)
        }
    }

    private func applyCustomHost() {
        monitor.stop()
        monitor.reset()
        startIfNeeded()
    }
}

// MARK: - Hero Card

private struct PingHeroCard: View {
    @ObservedObject var monitor: PingMonitor
    let hostText: String
    let onToggle: () -> Void

    var body: some View {
        let heroTint = monitor.status.heroTint

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        PulseDot(isActive: monitor.isRunning)
                        Text(monitor.status.label)
                            .appFont(size: 13, weight: .semibold, design: .rounded)
                            .foregroundStyle(AppTheme.ink.opacity(0.85))
                            .textCase(.uppercase)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(monitor.currentPing < 0 ? "--" : monitor.currentPing.fixed(0))
                            .appFont(size: 56, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.ink)
                            .contentTransition(.numericText())
                        Text("ms")
                            .appFont(size: 18, weight: .semibold, design: .rounded)
                            .foregroundStyle(AppTheme.ink.opacity(0.7))
                    }
                }

                Spacer(minLength: 12)

                Image(systemName: "waveform.path.ecg")
                    .appFont(size: 28, weight: .semibold)
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 58, height: 58)
                    .background(AppTheme.ink.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 0) {
                AppMetric(icon: "arrow.down", value: pingValue(monitor.minPing), unit: "ms", caption: "Min Ping")
                AppMetricDivider()
                AppMetric(icon: "equal", value: pingValue(monitor.avgPing), unit: "ms", caption: "Avg Ping")
                AppMetricDivider()
                AppMetric(icon: "arrow.up", value: pingValue(monitor.maxPing), unit: "ms", caption: "Max Ping")
            }
            .padding(.vertical, 12)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 10) {
                Button(action: onToggle) {
                    HStack(spacing: 8) {
                        Image(systemName: monitor.isRunning ? "stop.fill" : "play.fill")
                        Text(monitor.isRunning ? "Stop" : "Start")
                    }
                }
                .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, tint: heroTint))

                Text("Pinging \(hostText)...")
                    .appFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
        }
        .appHeroCard(tint: heroTint)
        .animation(.easeInOut(duration: 0.4), value: monitor.status)
    }

    private func pingValue(_ value: Double) -> String {
        value <= 0 ? "--" : value.fixed(0)
    }
}

/// Small live indicator with a repeating pulse ring while pinging.
private struct PulseDot: View {
    let isActive: Bool

    @State private var pulseScale: Double = 1
    @State private var pulseOpacity: Double = 0.6

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.ink, lineWidth: 2)
                .frame(width: 10, height: 10)
                .scaleEffect(pulseScale)
                .opacity(isActive ? pulseOpacity : 0)

            Circle()
                .fill(AppTheme.ink.opacity(isActive ? 1 : 0.45))
                .frame(width: 8, height: 8)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulseScale = 2.2
                pulseOpacity = 0
            }
        }
    }
}

// MARK: - Live Chart

private struct PingLiveChart: View {
    @ObservedObject var monitor: PingMonitor
    let hostText: String

    private static let routerColor = AppTheme.download

    private var maxChartValue: Double {
        let values = (monitor.pingHistory + monitor.routerHistory).map { $0.latency < 0 ? 0 : $0.latency }
        return max(20, (values.max() ?? 0) * 1.2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chart
            if !monitor.routerHistory.isEmpty {
                legend
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: monitor.status.color, text: Text(verbatim: hostText))
            legendItem(color: Self.routerColor, text: Text("Router"))
        }
        .appFont(size: 12, weight: .medium, design: .rounded)
        .foregroundStyle(AppTheme.secondaryText)
        .accessibilityHidden(true)
    }

    private func legendItem(color: Color, text: Text) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            text.lineLimit(1)
        }
    }

    private var chart: some View {
        let lineColor = monitor.status.color
        let maxChartValue = self.maxChartValue

        // Each line needs its own series, otherwise Charts joins the points
        // of both targets into one line.
        return Chart {
            ForEach(monitor.pingHistory) { sample in
                if sample.latency >= 0 {
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Latency", sample.latency),
                        series: .value("Target", "internet")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(lineColor)
                }
            }

            ForEach(monitor.routerHistory) { sample in
                if sample.latency >= 0 {
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Latency", sample.latency),
                        series: .value("Target", "router")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Self.routerColor)
                }
            }

            ForEach(monitor.pingHistory.filter { $0.latency < 0 }) { sample in
                PointMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Latency", maxChartValue * 0.9)
                )
                .symbolSize(40)
                .foregroundStyle(AppTheme.danger)
            }

            RectangleMark(
                xStart: .value("Start", Date().addingTimeInterval(-60)),
                xEnd: .value("End", Date()),
                yStart: .value("Low", 0),
                yEnd: .value("Excellent", 20)
            )
            .foregroundStyle(AppTheme.ping.opacity(0.1))
        }
        .chartXScale(domain: Date().addingTimeInterval(-60)...Date())
        .chartYScale(domain: 0...maxChartValue)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.minute().second()))
                    }
                }
                .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(AppTheme.separator)
                AxisValueLabel {
                    if let ping = value.as(Double.self) {
                        Text("\(Int(ping))")
                    }
                }
                .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .frame(height: 170)
    }
}

// MARK: - Wi-Fi or Provider

/// Router and internet host side by side, with the conclusion. Shown on Wi-Fi only.
private struct PingSplitSection: View {
    @ObservedObject var monitor: PingMonitor
    let hostText: String

    var body: some View {
        if let routerIP = monitor.routerIP, let diagnosis = monitor.diagnosis {
            AppSection("Wi-Fi or Provider?") {
                AppRow(icon: "wifi.router", tint: AppTheme.download, verbatimTitle: routerIP, subtitle: "Router") {
                    statsText(monitor.routerStats)
                }
                AppRowDivider()
                AppRow(icon: "globe", tint: monitor.status.color, verbatimTitle: hostText, subtitle: "Internet") {
                    statsText(monitor.pingHistory.isEmpty ? nil : LatencyStats(samples: monitor.pingHistory.map(\.latency)))
                }
                AppRowDivider()
                conclusion(diagnosis)
            }
        }
    }

    /// "4 ms · ±1 · 0%": average, jitter and loss.
    private func statsText(_ stats: LatencyStats?) -> some View {
        let text: String
        if let stats, stats.sent > stats.lost {
            let loss = stats.lossShare.formatted(.percent.precision(.fractionLength(0)))
            text = "\(stats.average.fixed(0)) ms · ±\(stats.jitter.fixed(0)) · \(loss)"
        } else if let stats, stats.sent > 0 {
            text = "100%"
        } else {
            text = "--"
        }
        return Text(verbatim: text)
            .appFont(size: 14, weight: .bold, design: .rounded)
            .monospacedDigit()
            .foregroundStyle(AppTheme.ink)
            .contentTransition(.numericText())
            .accessibilityLabel(stats.map { accessibilityText($0) } ?? Text("No data"))
    }

    private func accessibilityText(_ stats: LatencyStats) -> Text {
        Text("Average \(stats.average.fixed(0)) ms, jitter \(stats.jitter.fixed(0)) ms, \(stats.lost) of \(stats.sent) lost.")
    }

    private func conclusion(_ diagnosis: LatencyDiagnosis) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: diagnosis))
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(color(for: diagnosis))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title(for: diagnosis))
                    .appFont(size: 15, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                Text(message(for: diagnosis))
                    .appFont(size: 13, weight: .regular, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func icon(for diagnosis: LatencyDiagnosis) -> String {
        switch diagnosis {
        case .collecting: return "hourglass"
        case .healthy: return "checkmark.circle.fill"
        case .wifi: return "wifi.exclamationmark"
        case .beyondRouter: return "exclamationmark.triangle.fill"
        case .routerSilent: return "questionmark.circle.fill"
        }
    }

    private func color(for diagnosis: LatencyDiagnosis) -> Color {
        switch diagnosis {
        case .collecting, .routerSilent: return AppTheme.secondaryText
        case .healthy: return AppTheme.ping
        case .wifi, .beyondRouter: return AppTheme.warning
        }
    }

    private func title(for diagnosis: LatencyDiagnosis) -> LocalizedStringKey {
        switch diagnosis {
        case .collecting: return "Measuring…"
        case .healthy: return "Wi-Fi and provider look fine"
        case .wifi: return "The problem is your Wi-Fi"
        case .beyondRouter: return "The problem is beyond your router"
        case .routerSilent: return "Router doesn't answer"
        }
    }

    private func message(for diagnosis: LatencyDiagnosis) -> LocalizedStringKey {
        switch diagnosis {
        case .collecting:
            return "Keep this screen open for about 10 seconds."
        case .healthy:
            return "The router and the internet host both answer steadily."
        case .wifi:
            return "The router itself answers late, unevenly or not at all, so the problem is between this iPhone and the router. Move closer to the router or use 5 GHz Wi-Fi. The internet path can't be judged until Wi-Fi is stable."
        case .beyondRouter:
            return "The router answers quickly and steadily, so your Wi-Fi is fine. The delay or loss starts after the router: at your provider or on the way to the host you chose."
        case .routerSilent:
            return "Your router doesn't answer test connections, so Wi-Fi and the provider can't be told apart."
        }
    }
}

// MARK: - Statistics

private struct PingStatsRows: View {
    @ObservedObject var monitor: PingMonitor

    var body: some View {
        AppRow(icon: "paperplane.fill", tint: AppTheme.download, title: "Sent") {
            value("\(monitor.packetsSent)", color: AppTheme.ink)
        }
        AppRowDivider()
        AppRow(icon: "xmark.octagon.fill", tint: AppTheme.danger, title: "Lost") {
            value("\(monitor.packetsLost)", color: monitor.packetsLost > 0 ? AppTheme.danger : AppTheme.ink)
        }
        AppRowDivider()
        AppRow(icon: "percent", tint: Color(red: 0.93, green: 0.30, blue: 0.60), title: "Packet Loss") {
            value(
                (monitor.packetLossPercent / 100).formatted(.percent.precision(.fractionLength(0))),
                color: monitor.packetLossPercent > 0 ? AppTheme.danger : AppTheme.ink
            )
        }
        AppRowDivider()
        AppRow(icon: "waveform.path", tint: AppTheme.warning, title: "Jitter") {
            value(monitor.jitter.fixed(1) + " ms", color: monitor.jitter > 30 ? AppTheme.warning : AppTheme.ink)
        }
    }

    private func value(_ text: String, color: Color) -> some View {
        Text(text)
            .appFont(size: 17, weight: .bold, design: .rounded)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText())
    }
}

#Preview {
    PingMonitorView(monitor: PingMonitor())
        .preferredColorScheme(.dark)
}
