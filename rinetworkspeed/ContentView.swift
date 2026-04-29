//
//  ContentView.swift
//  rinetworkspeed
//
//  Created by Eray Kocer on 9.04.2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: NetworkStatsMonitor
    @ObservedObject var dataUsage: DataUsageMonitor
    @ObservedObject var speedTestManager: SpeedTestManager
    @ObservedObject var pingMonitor: PingMonitor
    @Binding var selectedTab: Int
    @AppStorage("speedUnit") private var speedUnit: String = "bytes"
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = true
    @State private var showingSpeedTest = false
    @State private var showingPingMonitor = false

    private let backgroundColor = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let downloadColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private let uploadColor = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                headerBar
                speedCards
                miniChartCard
                todayUsageCard
                connectionDetailsCard
                toolsCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(backgroundColor.ignoresSafeArea())
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

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tools")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 14) {
                toolButton(
                    title: "Speed Test",
                    subtitle: "Real download & upload measurement",
                    systemImage: "bolt.fill",
                    color: downloadColor
                ) {
                    showingSpeedTest = true
                }
                .proGated(feature: .speedTest)

                toolButton(
                    title: "Ping Monitor",
                    subtitle: "Live latency & packet loss",
                    systemImage: "dot.radiowaves.left.and.right",
                    color: uploadColor
                ) {
                    showingPingMonitor = true
                }
                .proGated(feature: .pingMonitor)
            }
        }
        .padding(18)
        .premiumCardStyle()
        .sheet(isPresented: $showingSpeedTest) {
            SpeedTestView(manager: speedTestManager)
        }
        .sheet(isPresented: $showingPingMonitor) {
            PingMonitorView(monitor: pingMonitor)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: activeConnectionIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(activeConnectionColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.connectionName)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(activeConnectionSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            Button {
                liveActivityEnabled.toggle()
            } label: {
                Image(systemName: liveActivityEnabled ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(liveActivityEnabled ? .red : .green)
            }
            .buttonStyle(.plain)
            .proGated(feature: .widget)
        }
        .padding(18)
        .premiumCardStyle()
    }

    private var speedCards: some View {
        HStack(spacing: 14) {
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

    private var miniChartCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Text("Last 60 sec")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.86))
                }

                Spacer()

                // Legend dots
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle().fill(downloadColor).frame(width: 6, height: 6)
                        Text("DL")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    HStack(spacing: 4) {
                        Circle().fill(uploadColor).frame(width: 6, height: 6)
                        Text("UL")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            CanvasSpeedChart(monitor: monitor)
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedTab = 1
                }
            } label: {
                HStack {
                    Text("Detailed Graph")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .premiumCardStyle()
    }

    private var todayUsageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today's Usage")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = 2
                    }
                } label: {
                    Text("Details ->")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 14) {
                usageTile(
                    title: "WiFi",
                    value: dataUsage.formatBytes(dataUsage.todayWifiBytes),
                    color: downloadColor
                )

                usageTile(
                    title: "Cellular",
                    value: dataUsage.formatBytes(dataUsage.todayCellularBytes),
                    color: uploadColor
                )
            }
        }
        .padding(18)
        .premiumCardStyle()
    }

    private var connectionDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connection Details")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            detailRow(title: "Ping / Latency", value: latencyText)
            detailRow(title: "WiFi RSSI", value: monitor.wifiSignalDescription)
            detailRow(title: "IP Address", value: monitor.ipAddress)
        }
        .padding(18)
        .premiumCardStyle()
    }

    private func speedCard(title: String, systemImage: String, color: Color, speed: Double) -> some View {
        let components = monitor.formattedSpeedComponents(speed)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(components.value)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(components.unit)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .transaction { t in t.animation = .easeOut(duration: 0.2) }

                Text(speedUnit == "bits" ? "Megabit speed format" : "Byte speed format")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .premiumCardStyle()
    }

    private func usageTile(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }

    private func toolButton(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            return .white.opacity(0.5)
        }
    }

    private var activeConnectionSubtitle: String {
        switch monitor.activeInterface {
        case .wifi:
            return "Wireless connection active"
        case .cellular:
            return "Mobile data active"
        case .none:
            return "No network connection detected"
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

    private var chartMaxSpeed: Double {
        let cutoff = Date().addingTimeInterval(-60)
        return monitor.history.lazy.filter { $0.timestamp >= cutoff }.reduce(0) { partialResult, sample in
            max(partialResult, sample.downloadSpeed, sample.uploadSpeed)
        }
    }

    private var latencyText: String {
        guard let latency = monitor.latencyMs else { return "--" }
        return String(format: "%.0f ms", latency)
    }
}

// MARK: - Canvas-based Speed Chart (high performance)

/// A lightweight chart rendered entirely via `Canvas` + `drawingGroup()`.
/// Unlike SwiftUI Charts, this avoids per-sample view allocation and heavy
/// layout passes, eliminating scroll jank on the homepage.
private struct CanvasSpeedChart: View {
    @ObservedObject var monitor: NetworkStatsMonitor

    // Resolved UIColors for Canvas (Color → CGColor is expensive in Canvas closures)
    private let dlStart = CGColor(red: 59/255, green: 130/255, blue: 246/255, alpha: 1)
    private let ulStart = CGColor(red: 249/255, green: 115/255, blue: 22/255, alpha: 1)

    private let downloadColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private let uploadColor = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // ── 1. Gather recent samples ──────────────────────────────
            let cutoff = Date().addingTimeInterval(-60)
            let samples = monitor.history.filter { $0.timestamp >= cutoff }
            guard samples.count >= 2 else {
                // Draw empty state grid lines only
                drawGrid(ctx: ctx, size: size, maxY: 1)
                return
            }

            let now = Date()
            let windowStart = now.addingTimeInterval(-60)

            // ── 2. Compute Y-axis scale ───────────────────────────────
            let rawMax = samples.reduce(0.0) {
                max($0, $1.downloadSpeed, $1.uploadSpeed)
            }
            let maxY = max(rawMax * 1.15, 1) // 15% headroom

            // ── 3. Draw subtle grid ───────────────────────────────────
            drawGrid(ctx: ctx, size: size, maxY: maxY)

            // ── 4. Map samples to points ──────────────────────────────
            func xFor(_ date: Date) -> CGFloat {
                CGFloat(date.timeIntervalSince(windowStart) / 60.0) * w
            }
            func yFor(_ value: Double) -> CGFloat {
                h - CGFloat(value / maxY) * h
            }

            let dlPoints = samples.map { CGPoint(x: xFor($0.timestamp), y: yFor($0.downloadSpeed)) }
            let ulPoints = samples.map { CGPoint(x: xFor($0.timestamp), y: yFor($0.uploadSpeed)) }

            // ── 5. Draw upload (behind) ───────────────────────────────
            drawSeries(
                ctx: ctx, size: size, points: ulPoints,
                lineColor: ulStart,
                fillTopColor: CGColor(red: 249/255, green: 115/255, blue: 22/255, alpha: 0.22),
                fillBottomColor: CGColor(red: 249/255, green: 115/255, blue: 22/255, alpha: 0.0),
                glowColor: CGColor(red: 249/255, green: 115/255, blue: 22/255, alpha: 0.35)
            )

            // ── 6. Draw download (front) ──────────────────────────────
            drawSeries(
                ctx: ctx, size: size, points: dlPoints,
                lineColor: dlStart,
                fillTopColor: CGColor(red: 59/255, green: 130/255, blue: 246/255, alpha: 0.28),
                fillBottomColor: CGColor(red: 59/255, green: 130/255, blue: 246/255, alpha: 0.0),
                glowColor: CGColor(red: 59/255, green: 130/255, blue: 246/255, alpha: 0.4)
            )

            // ── 7. Draw current value dots ────────────────────────────
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

    private func drawGrid(ctx: GraphicsContext, size: CGSize, maxY: Double) {
        let w = size.width, h = size.height
        let gridColor = Color.white.opacity(0.06)

        // Horizontal grid lines (4 lines)
        for i in 1...4 {
            let y = h * CGFloat(i) / 5.0
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: w, y: y))
            ctx.stroke(path, with: .color(gridColor),
                       style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        }

        // Vertical grid lines (every 10 seconds)
        for i in 1...5 {
            let x = w * CGFloat(i) / 6.0
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: h))
            ctx.stroke(path, with: .color(gridColor),
                       style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        }
    }

    private func drawSeries(
        ctx: GraphicsContext,
        size: CGSize,
        points: [CGPoint],
        lineColor: CGColor,
        fillTopColor: CGColor,
        fillBottomColor: CGColor,
        glowColor: CGColor
    ) {
        guard points.count >= 2 else { return }
        let w = size.width, h = size.height

        // Build smooth path using Catmull-Rom → Cubic Bézier conversion
        let linePath = catmullRomPath(through: points)

        // ── Gradient fill under the curve ─────────────────────────
        var fillPath = linePath
        fillPath.addLine(to: CGPoint(x: points.last!.x, y: h))
        fillPath.addLine(to: CGPoint(x: points.first!.x, y: h))
        fillPath.closeSubpath()

        let gradient = Gradient(stops: [
            .init(color: Color(cgColor: fillTopColor), location: 0),
            .init(color: Color(cgColor: fillBottomColor), location: 1)
        ])
        ctx.fill(fillPath, with: .linearGradient(gradient,
                                                  startPoint: CGPoint(x: w / 2, y: 0),
                                                  endPoint: CGPoint(x: w / 2, y: h)))

        // ── Glow line (wider, blurred) ────────────────────────────
        ctx.stroke(linePath,
                   with: .color(Color(cgColor: glowColor)),
                   style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

        // ── Main crisp line ───────────────────────────────────────
        ctx.stroke(linePath,
                   with: .color(Color(cgColor: lineColor)),
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

// MARK: - Card modifier

private struct PremiumCardModifier: ViewModifier {
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
        selectedTab: .constant(0)
    )
}

