//
//  ContentView.swift
//  rinetworkspeed
//
//  Created by Eray Kocer on 9.04.2026.
//

import SwiftUI

struct ContentView: View {
    // Not observed here: live values are read by the small subviews below
    // (hero, chart, usage, details), so per-tick updates don't re-render
    // the whole home screen.
    let monitor: NetworkStatsMonitor
    let dataUsage: DataUsageMonitor
    // Only handed to the sheets (which observe them); not observed here so
    // speed-test / ping ticks don't re-render the whole home screen.
    let speedTestManager: SpeedTestManager
    let pingMonitor: PingMonitor
    @Binding var selectedTab: Int
    @Binding var speedTestRequested: Bool
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = true
    @State private var showingSpeedTest = false
    @State private var showingPingMonitor = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                HomeLiveSpeedSection(monitor: monitor, liveActivityEnabled: $liveActivityEnabled)
                miniChartSection
                todayUsageSection
                connectionDetailsSection
                toolsSection
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .appPageBackground()
        // Attached to the page, not to the tools section: that section lives in
        // a LazyVStack and is not built until scrolled to, so a sheet attached
        // there cannot be presented programmatically (widget, control, etc.).
        .sheet(isPresented: $showingSpeedTest) {
            SpeedTestView(manager: speedTestManager)
        }
        .sheet(isPresented: $showingPingMonitor) {
            PingMonitorView(monitor: pingMonitor)
        }
        .task {
            // On a cold launch (widget, control, notification) the request is
            // already set before this view is in a window, and a sheet
            // presented that early is silently dropped.
            guard speedTestRequested else { return }
            try? await Task.sleep(for: .milliseconds(600))
            startRequestedSpeedTest()
        }
        .onChange(of: speedTestRequested) { _, isRequested in
            if isRequested { startRequestedSpeedTest() }
        }
        .onChange(of: liveActivityEnabled) { _, isEnabled in
            withAnimation(.easeInOut(duration: 0.3)) {
                if isEnabled {
                    monitor.applyLiveActivitySetting()
                } else {
                    monitor.stopLiveActivity()
                }
            }
        }
    }

    /// Opens the speed test sheet and starts a test, as requested from a
    /// widget, the Control Center control or a notification action.
    private func startRequestedSpeedTest() {
        guard speedTestRequested else { return }
        speedTestRequested = false

        showingPingMonitor = false
        showingSpeedTest = true

        let isRunning: Bool
        switch speedTestManager.state {
        case .pingTesting, .downloadTesting, .transitionToUpload, .uploadTesting:
            isRunning = true
        case .idle, .finished, .failed:
            isRunning = false
        }
        if !isRunning {
            Task { await speedTestManager.startTest() }
        }
    }

    // MARK: Sections

    private var miniChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AppSectionHeader("Last 60 sec")
                Spacer()
                HStack(spacing: 12) {
                    legendDot(color: AppTheme.download, label: "DL")
                    legendDot(color: AppTheme.upload, label: "UL")
                }
                .padding(.trailing, 4)
            }

            VStack(spacing: 0) {
                CanvasSpeedChart(monitor: monitor)
                    .frame(height: 160)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Download and upload speed over the last 60 seconds"))
                    .padding(.horizontal, 14)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                AppRowDivider(leadingInset: 0)

                Button {
                    selectedTab = 1
                } label: {
                    AppRow(icon: "chart.xyaxis.line", tint: AppTheme.accent, title: "Detailed Graph") {
                        AppChevron()
                    }
                }
                .buttonStyle(AppRowButtonStyle())
            }
            .appCard(padding: nil)
        }
    }

    private var todayUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AppSectionHeader("Today's Usage")
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = 2
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Details")
                        Image(systemName: "chevron.right")
                            .appFont(size: 11, weight: .bold)
                    }
                    .appFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.download)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }

            HomeUsageRows(dataUsage: dataUsage)
                .appCard(padding: nil)
        }
    }

    private var connectionDetailsSection: some View {
        AppSection("Connection Details") {
            HomeConnectionRows(monitor: monitor)
        }
    }

    private var toolsSection: some View {
        AppSection("Tools") {
            Button {
                showingSpeedTest = true
            } label: {
                AppRow(
                    icon: "bolt.fill",
                    tint: AppTheme.download,
                    title: "Speed Test",
                    subtitle: "Real download & upload measurement"
                ) {
                    AppChevron()
                }
            }
            .buttonStyle(AppRowButtonStyle())

            AppRowDivider()

            Button {
                showingPingMonitor = true
            } label: {
                AppRow(
                    icon: "dot.radiowaves.left.and.right",
                    tint: AppTheme.upload,
                    title: "Ping Monitor",
                    subtitle: "Live latency & packet loss"
                ) {
                    AppChevron()
                }
            }
            .buttonStyle(AppRowButtonStyle())
        }
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

// MARK: - Live Speed Header

/// Original header bar + Download/Upload speed cards. Observes the monitor on
/// its own so only this part re-renders per tick.
private struct HomeLiveSpeedSection: View {
    @ObservedObject var monitor: NetworkStatsMonitor
    @Binding var liveActivityEnabled: Bool
    @AppStorage("speedUnit") private var speedUnit: String = "bytes"

    private let downloadColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private let uploadColor = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    var body: some View {
        VStack(spacing: 16) {
            headerBar
            speedCards
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: activeConnectionIcon)
                    .appFont(size: 18, weight: .semibold)
                    .foregroundStyle(activeConnectionColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.connectionName)
                        .appFont(size: 19, weight: .bold, design: .rounded)
                        .foregroundStyle(AppTheme.ink)
                    Text(activeConnectionSubtitle)
                        .appFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AppTheme.ink.opacity(0.5))
                }
            }

            Spacer()

            Button {
                liveActivityEnabled.toggle()
            } label: {
                Image(systemName: liveActivityEnabled ? "stop.circle.fill" : "play.circle.fill")
                    .appFont(size: 28, weight: .semibold)
                    .foregroundStyle(liveActivityEnabled ? .red : .green)
                    .accessibilityLabel(liveActivityEnabled ? Text("Stop Live Activity") : Text("Start Live Activity"))
            }
            .buttonStyle(.plain)
            .proGated(feature: .widgets)
        }
        .padding(18)
        .premiumCardStyle()
    }

    private var speedCards: some View {
        AppAdaptiveStack(spacing: 14) {
            speedCard(
                title: "Download",
                systemImage: "arrow.down.circle.fill",
                color: downloadColor,
                speed: primaryDownloadSpeed
            )

            speedCard(
                title: "Upload",
                systemImage: "arrow.up.circle.fill",
                color: uploadColor,
                speed: primaryUploadSpeed
            )
        }
    }

    private func speedCard(title: LocalizedStringKey, systemImage: String, color: Color, speed: Double) -> some View {
        let components = monitor.formattedSpeedComponents(speed)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .appFont(size: 24, weight: .semibold)
                    .foregroundStyle(color)

                Text(title)
                    .appFont(size: 18, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.ink.opacity(0.82))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(components.value)
                        .appFont(size: 38, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.ink)
                        .contentTransition(.numericText())
                        // Shrink long values (e.g. "1024.0") instead of wrapping.
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(components.unit)
                        .appFont(size: 16, weight: .semibold, design: .rounded)
                        .foregroundStyle(AppTheme.ink.opacity(0.58))
                        .lineLimit(1)
                        .fixedSize()
                }
                .transaction { t in t.animation = .easeOut(duration: 0.2) }

                Text(speedUnit == "bits" ? "Megabit speed format" : "Byte speed format")
                    .appFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AppTheme.ink.opacity(0.42))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .premiumCardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: "\(components.value) \(components.unit)"))
    }

    private var activeConnectionIcon: String {
        switch monitor.activeInterface {
        case .wifi:
            return "wifi"
        case .cellular:
            return "antenna.radiowaves.left.and.right"
        case .none:
            return "wifi.slash"
        }
    }

    private var activeConnectionColor: Color {
        switch monitor.activeInterface {
        case .wifi:
            return downloadColor
        case .cellular:
            return uploadColor
        case .none:
            return AppTheme.ink.opacity(0.5)
        }
    }

    private var activeConnectionSubtitle: String {
        switch monitor.activeInterface {
        case .wifi:
            return String(localized: "Wireless connection active")
        case .cellular:
            return String(localized: "Mobile data active")
        case .none:
            return String(localized: "No network connection detected")
        }
    }

    private var primaryDownloadSpeed: Double {
        switch monitor.activeInterface {
        case .wifi:
            return monitor.wifiDownloadSpeed
        case .cellular:
            return monitor.cellularDownloadSpeed
        case .none:
            return monitor.downloadSpeed
        }
    }

    private var primaryUploadSpeed: Double {
        switch monitor.activeInterface {
        case .wifi:
            return monitor.wifiUploadSpeed
        case .cellular:
            return monitor.cellularUploadSpeed
        case .none:
            return monitor.uploadSpeed
        }
    }
}

// MARK: - Usage Rows

private struct HomeUsageRows: View {
    @ObservedObject var dataUsage: DataUsageMonitor

    var body: some View {
        VStack(spacing: 0) {
            AppRow(icon: "wifi", tint: AppTheme.download, title: "WiFi") {
                valueText(dataUsage.formatBytes(dataUsage.todayWifiBytes))
            }
            AppRowDivider()
            AppRow(icon: "antenna.radiowaves.left.and.right", tint: AppTheme.upload, title: "Cellular") {
                valueText(dataUsage.formatBytes(dataUsage.todayCellularBytes))
            }
        }
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .appFont(size: 17, weight: .bold, design: .rounded)
            .monospacedDigit()
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(1)
    }
}

// MARK: - Connection Rows

private struct HomeConnectionRows: View {
    @ObservedObject var monitor: NetworkStatsMonitor

    var body: some View {
        AppRow(icon: "timer", tint: AppTheme.ping, title: "Ping / Latency") {
            valueText(latencyText)
        }
        AppRowDivider()
        AppRow(icon: "wifi", tint: AppTheme.download, title: "Wi-Fi") {
            valueText(monitor.wifiSignalDescription)
        }
        AppRowDivider()
        AppRow(icon: "network", tint: AppTheme.accent, title: "IP Address") {
            valueText(monitor.ipAddress)
        }
    }

    private var latencyText: String {
        guard let latency = monitor.latencyMs else { return "--" }
        return latency.fixed(0) + " ms"
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .appFont(size: 15, weight: .semibold, design: .rounded)
            .monospacedDigit()
            .foregroundStyle(AppTheme.secondaryText)
            .lineLimit(1)
            .textSelection(.enabled)
    }
}

// MARK: - Canvas-based Speed Chart (high performance)

/// A lightweight chart rendered entirely via `Canvas` + `drawingGroup()`.
/// Unlike SwiftUI Charts, this avoids per-sample view allocation and heavy
/// layout passes, eliminating scroll jank on the homepage.
private struct CanvasSpeedChart: View {
    @ObservedObject var monitor: NetworkStatsMonitor

    private let downloadColor = AppTheme.download
    private let uploadColor = AppTheme.upload

    /// Matches the "Speed Unit" setting so axis labels use the same unit as the rest of the app.
    @AppStorage("speedUnit") private var speedUnit: String = "bytes"

    // Space reserved for the speed axis (left) and time axis (bottom).
    private let leftGutter: CGFloat = 50
    private let bottomGutter: CGFloat = 16
    private let topInset: CGFloat = 6
    private let windowSeconds: TimeInterval = 60

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(
                x: leftGutter,
                y: topInset,
                width: max(size.width - leftGutter, 1),
                height: max(size.height - topInset - bottomGutter, 1)
            )

            // ── 1. Gather recent samples ──────────────────────────────
            let now = Date()
            let windowStart = now.addingTimeInterval(-windowSeconds)
            let samples = monitor.history.samples(since: windowStart)

            // ── 2. Compute a "nice" Y-axis scale ──────────────────────
            let rawMax = samples.reduce(0.0) {
                max($0, $1.downloadSpeed, $1.uploadSpeed)
            }
            let scale = AxisScale(maxBytesPerSecond: rawMax, usesBits: speedUnit == "bits")

            // ── 3. Draw grid + axis labels ────────────────────────────
            drawGrid(ctx: ctx, plot: plot, scale: scale)
            drawTimeAxis(ctx: ctx, plot: plot)

            guard samples.count >= 2 else { return }

            // ── 4. Map samples to points ──────────────────────────────
            func xFor(_ date: Date) -> CGFloat {
                plot.minX + CGFloat(date.timeIntervalSince(windowStart) / windowSeconds) * plot.width
            }
            func yFor(_ value: Double) -> CGFloat {
                plot.maxY - CGFloat(min(value / scale.maxBytesPerSecond, 1)) * plot.height
            }

            let dlPoints = samples.map { CGPoint(x: xFor($0.timestamp), y: yFor($0.downloadSpeed)) }
            let ulPoints = samples.map { CGPoint(x: xFor($0.timestamp), y: yFor($0.uploadSpeed)) }

            // Keep the curves inside the plot area (Catmull-Rom can overshoot slightly).
            var plotCtx = ctx
            plotCtx.clip(to: Path(plot.insetBy(dx: 0, dy: -3)))

            // ── 5. Draw upload (behind) ───────────────────────────────
            drawSeries(
                ctx: plotCtx, plot: plot, points: ulPoints,
                color: uploadColor, fillOpacity: 0.22, glowOpacity: 0.35
            )

            // ── 6. Draw download (front) ──────────────────────────────
            drawSeries(
                ctx: plotCtx, plot: plot, points: dlPoints,
                color: downloadColor, fillOpacity: 0.28, glowOpacity: 0.4
            )

            // ── 7. Peak marker for the visible window ─────────────────
            if rawMax > 0 {
                drawPeakLine(ctx: ctx, plot: plot, y: yFor(rawMax), label: scale.peakLabel(for: rawMax))
            }

            // ── 8. Draw current value dots ────────────────────────────
            if let lastDL = dlPoints.last {
                let dotRect = CGRect(x: lastDL.x - 3, y: lastDL.y - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: dotRect.insetBy(dx: -3, dy: -3)),
                         with: .color(downloadColor.opacity(0.3)))
                ctx.fill(Path(ellipseIn: dotRect),
                         with: .color(downloadColor))
            }
            if let lastUL = ulPoints.last {
                let dotRect = CGRect(x: lastUL.x - 3, y: lastUL.y - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: dotRect.insetBy(dx: -3, dy: -3)),
                         with: .color(uploadColor.opacity(0.3)))
                ctx.fill(Path(ellipseIn: dotRect),
                         with: .color(uploadColor))
            }
        }
        .drawingGroup() // GPU-composited render — eliminates scroll jank
        .transaction { t in t.animation = nil } // never animate canvas redraws
    }

    // MARK: - Drawing helpers

    private func axisText(_ string: String) -> Text {
        Text(verbatim: string)
            .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(AppTheme.tertiaryText)
    }

    private func drawGrid(ctx: GraphicsContext, plot: CGRect, scale: AxisScale) {
        let gridColor = AppTheme.separator

        // Horizontal grid lines with speed labels (one per tick, 0 at the bottom).
        for tick in 0...scale.tickCount {
            let fraction = CGFloat(tick) / CGFloat(scale.tickCount)
            let y = plot.maxY - fraction * plot.height
            var path = Path()
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
            ctx.stroke(path, with: .color(tick == 0 ? AppTheme.ink.opacity(0.14) : gridColor),
                       style: StrokeStyle(lineWidth: 0.5, dash: tick == 0 ? [] : [4, 4]))

            ctx.draw(axisText(scale.label(forTick: tick)),
                     at: CGPoint(x: plot.minX - 6, y: y),
                     anchor: .trailing)
        }

        // Vertical grid lines (every 10 seconds)
        for i in 1...5 {
            let x = plot.minX + plot.width * CGFloat(i) / 6.0
            var path = Path()
            path.move(to: CGPoint(x: x, y: plot.minY))
            path.addLine(to: CGPoint(x: x, y: plot.maxY))
            ctx.stroke(path, with: .color(gridColor),
                       style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        }
    }

    private func drawTimeAxis(ctx: GraphicsContext, plot: CGRect) {
        // Labels every 15 s; the right edge is "now".
        let labels: [(fraction: CGFloat, text: String, anchor: UnitPoint)] = [
            (0, "-60s", .topLeading),
            (0.25, "-45s", .top),
            (0.5, "-30s", .top),
            (0.75, "-15s", .top),
            (1, String(localized: "now"), .topTrailing)
        ]
        for label in labels {
            ctx.draw(axisText(label.text),
                     at: CGPoint(x: plot.minX + label.fraction * plot.width, y: plot.maxY + 3),
                     anchor: label.anchor)
        }
    }

    private func drawPeakLine(ctx: GraphicsContext, plot: CGRect, y: CGFloat, label: String) {
        var path = Path()
        path.move(to: CGPoint(x: plot.minX, y: y))
        path.addLine(to: CGPoint(x: plot.maxX, y: y))
        ctx.stroke(path, with: .color(AppTheme.ink.opacity(0.28)),
                   style: StrokeStyle(lineWidth: 0.75, dash: [2, 3]))

        let text = Text(verbatim: label)
            .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(AppTheme.ink.opacity(0.75))
        // Place the label just above the line, or below it when the peak touches the top.
        let labelY = y - plot.minY > 12 ? y - 2 : y + 2
        ctx.draw(text,
                 at: CGPoint(x: plot.minX + 4, y: labelY),
                 anchor: y - plot.minY > 12 ? .bottomLeading : .topLeading)
    }

    private func drawSeries(
        ctx: GraphicsContext,
        plot: CGRect,
        points: [CGPoint],
        color: Color,
        fillOpacity: Double,
        glowOpacity: Double
    ) {
        guard points.count >= 2, let first = points.first, let last = points.last else { return }

        // Build smooth path using Catmull-Rom → Cubic Bézier conversion
        let linePath = catmullRomPath(through: points)

        // ── Flat fill under the curve ─────────────────────────────
        var fillPath = linePath
        fillPath.addLine(to: CGPoint(x: last.x, y: plot.maxY))
        fillPath.addLine(to: CGPoint(x: first.x, y: plot.maxY))
        fillPath.closeSubpath()

        ctx.fill(fillPath, with: .color(color.opacity(fillOpacity * 0.5)))

        // ── Glow line (wider, blurred) ────────────────────────────
        ctx.stroke(linePath,
                   with: .color(color.opacity(glowOpacity)),
                   style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

        // ── Main crisp line ───────────────────────────────────────
        ctx.stroke(linePath,
                   with: .color(color),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    /// Converts a set of points into a smooth Catmull-Rom spline path
    /// (approximated via cubic Bézier segments).
    private func catmullRomPath(through points: [CGPoint], alpha: CGFloat = 0.5) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for i in 0..<points.count - 1 {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[min(i + 1, points.count - 1)]
            let p3 = points[min(i + 2, points.count - 1)]

            let d1 = distance(p0, p1)
            let d2 = distance(p1, p2)
            let d3 = distance(p2, p3)

            let d1a = pow(d1, alpha)
            let d2a = pow(d2, alpha)
            let d3a = pow(d3, alpha)

            var b1: CGPoint
            if abs(d1a) < 1e-6 {
                b1 = p1
            } else {
                b1 = CGPoint(
                    x: (d1a * d1a * p2.x - d2a * d2a * p0.x + (2 * d1a * d1a + 3 * d1a * d2a + d2a * d2a) * p1.x) / (3 * d1a * (d1a + d2a)),
                    y: (d1a * d1a * p2.y - d2a * d2a * p0.y + (2 * d1a * d1a + 3 * d1a * d2a + d2a * d2a) * p1.y) / (3 * d1a * (d1a + d2a))
                )
            }

            var b2: CGPoint
            if abs(d3a) < 1e-6 {
                b2 = p2
            } else {
                b2 = CGPoint(
                    x: (d3a * d3a * p1.x - d2a * d2a * p3.x + (2 * d3a * d3a + 3 * d3a * d2a + d2a * d2a) * p2.x) / (3 * d3a * (d3a + d2a)),
                    y: (d3a * d3a * p1.y - d2a * d2a * p3.y + (2 * d3a * d3a + 3 * d3a * d2a + d2a * d2a) * p2.y) / (3 * d3a * (d3a + d2a))
                )
            }

            path.addCurve(to: p2, control1: b1, control2: b2)
        }

        return path
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
    }
}

// MARK: - Chart axis scale

/// Rounds the chart's Y range up to a "nice" value (1/2/2.5/5 × 10ⁿ) in the
/// user's display unit, so axis labels read e.g. 0 · 5 · 10 · 15 · 20 MB/s.
private struct AxisScale {
    let maxBytesPerSecond: Double
    let tickCount: Int
    private let step: Double
    private let unitDivisor: Double
    private let unit: String
    private let usesBits: Bool

    init(maxBytesPerSecond rawMax: Double, usesBits: Bool) {
        let units = usesBits
            ? ["bps", "Kbps", "Mbps", "Gbps", "Tbps"]
            : ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        let multiplier: Double = usesBits ? 8 : 1

        // Never collapse to a zero range; 1 KB/s is the smallest full-scale value.
        var display = max(rawMax * multiplier * 1.1, 1024 * multiplier)
        var unitIndex = 0
        var divisor = 1.0
        while display >= 1024, unitIndex < units.count - 1 {
            display /= 1024
            divisor *= 1024
            unitIndex += 1
        }

        let step = AxisScale.niceStep(for: display / 4)
        let ticks = max(1, Int((display / step).rounded(.up)))

        self.step = step
        self.tickCount = ticks
        self.unitDivisor = divisor
        self.unit = units[unitIndex]
        self.usesBits = usesBits
        self.maxBytesPerSecond = Double(ticks) * step * divisor / multiplier
    }

    func label(forTick tick: Int) -> String {
        guard tick > 0 else { return "0" }
        return "\(Self.format(Double(tick) * step)) \(unit)"
    }

    func peakLabel(for bytesPerSecond: Double) -> String {
        let value = bytesPerSecond * (usesBits ? 8 : 1) / unitDivisor
        return String(localized: "Peak \(value.fixed(1)) \(unit)")
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? value.fixed(0) : value.fixed(1)
    }

    private static func niceStep(for rough: Double) -> Double {
        guard rough > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(rough)))
        let normalized = rough / magnitude
        let nice: Double
        switch normalized {
        case ...1: nice = 1
        case ...2: nice = 2
        case ...2.5: nice = 2.5
        case ...5: nice = 5
        default: nice = 10
        }
        return nice * magnitude
    }
}

// MARK: - Card modifier

private struct PremiumCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(AppTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
    }
}

private extension View {
    func premiumCardStyle() -> some View {
        modifier(PremiumCardModifier())
    }
}

#Preview {
    ContentView(
        monitor: NetworkStatsMonitor(),
        dataUsage: DataUsageMonitor(),
        speedTestManager: SpeedTestManager(),
        pingMonitor: PingMonitor(),
        selectedTab: .constant(0),
        speedTestRequested: .constant(false)
    )
}
