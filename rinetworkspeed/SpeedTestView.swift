//
//  SpeedTestView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import UIKit

// MARK: - SpeedometerView

private struct SpeedometerView: View {
    let progress: Double   // 0–1
    let maxSpeed: Double
    let valueText: String
    let unitText: String
    let subtitle: String
    let glowColor: Color

    // Circle.trim(from:0) starts at 3-o'clock, goes clockwise.
    // rotationEffect(.degrees(startDeg)) rotates clockwise → arc begins at 8-o'clock.
    private static let startDeg: Double = 150   // 8-o'clock (clockwise from right)
    private static let sweepDeg: Double = 240   // total arc span
    private static let trackFrac: Double = sweepDeg / 360   // ~0.667

    private var fillFrac: Double { max(0, min(progress, 1)) * Self.trackFrac }

    // Swift UIrotationEffect: 0° = up (12-o-clock), clockwise positive.
    // addArc angle for arc end = startDeg + progress * sweepDeg (0° = right convention).
    // Convert: rotationEffect = arcAngle − 270
    private var needleRot: Double {
        (Self.startDeg + max(0, min(progress, 1)) * Self.sweepDeg) - 270
    }

    var body: some View {
        GeometryReader { geo in
            let side    = min(geo.size.width, geo.size.height)
            let trackR  = side * 0.40
            let trackD  = trackR * 2
            let lw: CGFloat = 10
            let needleL = trackR * 0.94
            let hubSz   = side * 0.058

            ZStack {
                // ── 1. Radial background glow ─────────────────────────
                RadialGradient(
                    colors: [Color(white: 0.13).opacity(0.40), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: side * 0.50
                )
                .frame(width: side, height: side)
                .clipShape(Circle())

                // ── 2. Background track arc (grey, via trim — no artifacts) ──
                Circle()
                    .trim(from: 0, to: Self.trackFrac)
                    .stroke(Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    .frame(width: trackD, height: trackD)
                    .rotationEffect(.degrees(Self.startDeg))

                // ── 3. Gradient fill arc (MASK TRICK) ────────────────
                // AngularGradient is on a STATIC full circle — never animated.
                // Only the mask (trim) changes. Guaranteed zero composition artifacts.
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color(hue: 0.335, saturation: 0.90, brightness: 0.88), location: 0.00),
                                .init(color: Color(hue: 0.230, saturation: 0.85, brightness: 0.90), location: 0.25),
                                .init(color: Color(hue: 0.155, saturation: 0.95, brightness: 0.92), location: 0.50),
                                .init(color: Color(hue: 0.070, saturation: 1.00, brightness: 0.92), location: 0.75),
                                .init(color: Color(hue: 0.000, saturation: 1.00, brightness: 0.90), location: 1.00)
                            ]),
                            center: .center,
                            startAngle: .degrees(Self.startDeg),
                            endAngle:   .degrees(Self.startDeg + Self.sweepDeg)
                        ),
                        lineWidth: lw
                    )
                    .frame(width: trackD, height: trackD)
                    .mask(alignment: .center) {
                        // Mask is 2pt wider to avoid fringing at round caps
                        Circle()
                            .trim(from: 0, to: fillFrac)
                            .stroke(style: StrokeStyle(lineWidth: lw + 2, lineCap: .round))
                            .frame(width: trackD, height: trackD)
                            .rotationEffect(.degrees(Self.startDeg))
                    }
                    .shadow(color: glowColor.opacity(0.55), radius: 10)

                // ── 4. Tick marks (pure Canvas, only reads maxSpeed — never progress) ──
                SpeedometerScaleView(maxSpeed: maxSpeed)
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)

                // ── 5. Needle ─────────────────────────────────────────
                // rotationEffect anchor=.bottom, then offset centres the pivot
                NeedleShape()
                    .fill(LinearGradient(
                        colors: [.white, Color(white: 0.58)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: side * 0.017, height: needleL)
                    .shadow(color: .white.opacity(0.42), radius: 4)
                    .rotationEffect(.degrees(needleRot), anchor: .bottom)
                    .offset(y: -needleL / 2)

                // ── 6. Centre hub ─────────────────────────────────────
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(white: 0.96), Color(white: 0.38)],
                        center: .center,
                        startRadius: 0,
                        endRadius: hubSz / 2
                    ))
                    .frame(width: hubSz)
                    .shadow(color: .white.opacity(0.40), radius: 5)

                // ── 7. Speed value text ───────────────────────────────
                VStack(spacing: 1) {
                    Text(valueText)
                        .font(.system(size: side * 0.115, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(unitText)
                        .font(.system(size: side * 0.042, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(subtitle)
                        .font(.system(size: side * 0.036, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .offset(y: side * 0.17)
            }
        }
    }
}

private struct SpeedometerScaleView: View, Equatable {
    let maxSpeed: Double

    private static let startDeg: Double = 150
    private static let sweepDeg: Double = 240

    static func == (lhs: SpeedometerScaleView, rhs: SpeedometerScaleView) -> Bool {
        lhs.maxSpeed == rhs.maxSpeed
    }

    var body: some View {
        Canvas { ctx, size in
            let s  = min(size.width, size.height)
            let cx = size.width / 2
            let cy = size.height / 2
            let radius = s * 0.40

            let step: Double
            if maxSpeed <= 50 {
                step = 10
            } else if maxSpeed <= 200 {
                step = 20
            } else if maxSpeed <= 500 {
                step = 50
            } else {
                step = 100
            }

            let minorStep = step / 4

            func point(for value: Double, radius: CGFloat) -> CGPoint {
                let degrees = Self.startDeg + (value / maxSpeed) * Self.sweepDeg
                let radians = degrees * .pi / 180
                return CGPoint(
                    x: cx + radius * CGFloat(cos(radians)),
                    y: cy + radius * CGFloat(sin(radians))
                )
            }

            var value = 0.0
            while value <= maxSpeed + 0.001 {
                let isMajorTick = value.truncatingRemainder(dividingBy: step) < 0.001
                var path = Path()

                if isMajorTick {
                    path.move(to: point(for: value, radius: radius - s * 0.005))
                    path.addLine(to: point(for: value, radius: radius - s * 0.048))
                    ctx.stroke(path, with: .color(.white.opacity(0.70)), lineWidth: 2)

                    let label = value >= 1000 ? "\(Int(value / 1000))k" : "\(Int(value))"
                    ctx.draw(
                        Text(label)
                            .font(.system(size: s * 0.033, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.65)),
                        at: point(for: value, radius: radius + s * 0.074)
                    )
                } else {
                    path.move(to: point(for: value, radius: radius - s * 0.005))
                    path.addLine(to: point(for: value, radius: radius - s * 0.026))
                    ctx.stroke(path, with: .color(.white.opacity(0.20)), lineWidth: 1)
                }

                value += minorStep
            }
        }
        .id(maxSpeed)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

// MARK: - NeedleShape

private struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w / 2, y: 0))
        p.addLine(to: CGPoint(x: w, y: h * 0.86))
        p.addArc(center: CGPoint(x: w / 2, y: h * 0.86),
                 radius: w / 2,
                 startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - WaveView

private struct SpeedWaveView: View {
    let amplitude: Double   // 0–1
    let color: Color

    var body: some View {
        // Paused while flat so the canvas isn't redrawn every frame when idle.
        TimelineView(.animation(paused: amplitude < 0.001)) { timeline in
            // One full wave cycle every 1.8 s, derived from the timeline date.
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.8) / 1.8 * 2 * Double.pi
            Canvas { ctx, size in
                let amp = amplitude * 22
                let freq = 2.0 * Double.pi / size.width
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                for x in stride(from: 0, through: size.width, by: 2) {
                    let y = size.height / 2 + amp * sin(freq * x * 2.5 + phase)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                ctx.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 2)
            }
        }
    }
}

// MARK: - PhaseStepperView

private struct PhaseStepperView: View {
    enum Phase: Int { case ping = 0, download = 1, upload = 2 }
    let current: Phase?          // nil = idle / done

    private func color(for phase: Phase) -> Color {
        switch phase {
        case .ping:     return AppTheme.ping
        case .download: return AppTheme.download
        case .upload:   return AppTheme.upload
        }
    }

    private func label(for phase: Phase) -> String {
        switch phase {
        case .ping:     return "PING"
        case .download: return "DOWNLOAD"
        case .upload:   return "UPLOAD"
        }
    }

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach([Phase.ping, .download, .upload], id: \.rawValue) { phase in
                let isDone    = current.map { phase.rawValue < $0.rawValue } ?? false
                let isActive  = current == phase

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(isDone ? color(for: phase) : Color.white.opacity(0.06))
                            .frame(width: 26, height: 26)
                            .scaleEffect(isActive && pulse ? 1.18 : 1)
                            .animation(
                                isActive ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default,
                                value: pulse
                            )
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle()
                                .stroke(
                                    isActive ? color(for: phase) : AppTheme.cardStroke,
                                    lineWidth: 2
                                )
                                .frame(width: 26, height: 26)
                            if isActive {
                                Circle()
                                    .fill(color(for: phase))
                                    .frame(width: 10, height: 10)
                                    .shadow(color: color(for: phase).opacity(0.8), radius: 4)
                            }
                        }
                    }
                    Text(label(for: phase))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(
                            isActive  ? color(for: phase) :
                            isDone    ? AppTheme.secondaryText :
                                        AppTheme.tertiaryText
                        )
                }

                if phase != .upload {
                    Capsule()
                        .fill(isDone ? color(for: phase).opacity(0.6) : AppTheme.separator)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 20)
                }
            }
        }
        .onAppear { pulse = true }
        .onChange(of: current) { _, _ in pulse = true }
    }
}

// MARK: - SpeedTestView

struct SpeedTestView: View {
    @ObservedObject var manager: SpeedTestManager
    @StateObject private var wifiInfoManager = WiFiInfoManager()
    @State private var animatePulse = false
    @State private var isNetworkDetailsExpanded = false
    @State private var isHistoryExpanded = true
    @State private var showShareSheet = false
    @State private var shimmerPhase: CGFloat = 0
    @State private var needleProgress: Double = 0

    private let pingColor     = AppTheme.ping
    private let downloadColor = AppTheme.download
    private let uploadColor   = AppTheme.upload
    /// Full-scale value of the speedometer in Mbps; user-selectable (250 / 500 / 1k).
    @AppStorage("gaugeMaxSpeed") private var gaugeMaxSpeed: Double = 1_000
    private let gaugeScaleOptions: [Double] = [250, 500, 1_000]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    VStack(spacing: 14) {
                        // ── Hero gauge (with phase stepper while testing) ──
                        speedometerSection

                        // ── Live metrics row ─────────────────────────────
                        if isTesting || manager.state == .finished {
                            liveMetricsRow
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // ── Control button ───────────────────────────────
                        controlButton
                    }

                    // ── Result cards (after test) ────────────────────────
                    if manager.state == .finished {
                        VStack(spacing: 14) {
                            resultCards
                            shareCardButton
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // ── History ──────────────────────────────────────────
                    historySection

                    // ── WiFi Details ─────────────────────────────────────
                    if manager.state == .finished {
                        networkDetailsSection
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: manager.state)
            }
            .appPageBackground()
            .navigationTitle("Speed Test")
        }
        .appPageBackground()
        .sheet(isPresented: $showShareSheet) {
            if let latest = manager.history.first {
                SpeedSharePreviewSheet(
                    result: latest,
                    ssid: wifiInfoManager.ssid,
                    isWifi: wifiInfoManager.ssid != nil
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            animatePulse = isTesting
        }
        .task {
            await wifiInfoManager.refresh()
        }
        .onChange(of: isTesting) { _, newValue in
            animatePulse = newValue
            if !newValue {
                needleProgress = 0
            }
        }
        .onChange(of: manager.displayDownloadSpeed) { _, _ in updateNeedle() }
        .onChange(of: manager.displayUploadSpeed)   { _, _ in updateNeedle() }
        .onChange(of: manager.state) { _, newState in
            if newState == .finished {
                // Return needle to 0 smoothly
                withAnimation(.interpolatingSpring(stiffness: 20, damping: 8)) {
                    needleProgress = 0
                }
            } else if newState == .transitionToUpload {
                // Force needle to zero during download→upload transition
                withAnimation(.interpolatingSpring(stiffness: 20, damping: 8)) {
                    needleProgress = 0
                }
            }
        }
    }

    // MARK: - Speedometer section

    private var gaugeScalePicker: some View {
        Picker("Gauge Scale", selection: $gaugeMaxSpeed) {
            ForEach(gaugeScaleOptions, id: \.self) { option in
                Text(option >= 1_000 ? "0–\(Int(option / 1_000))k" : "0–\(Int(option))")
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .onChange(of: gaugeMaxSpeed) { _, _ in
            updateNeedle()
        }
    }

    /// Hero card holding the gauge: dark glass surface lit by the current phase color.
    private var speedometerSection: some View {
        VStack(spacing: 12) {
            if isTesting || manager.state == .finished {
                PhaseStepperView(current: currentPhase)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .scale))
            }

            SpeedometerView(
                progress: needleProgress,
                maxSpeed: gaugeMaxSpeed,
                valueText: formattedCurrentSpeed.value,
                unitText: formattedCurrentSpeed.unit,
                subtitle: gaugeSubtitle,
                glowColor: glowColor
            )
            .aspectRatio(1.05, contentMode: .fit)
            // The arc leaves empty space below its endpoints; tuck the wave up into it.
            .padding(.bottom, -36)

            // Wave line
            SpeedWaveView(amplitude: needleProgress, color: glowColor)
                .frame(height: 36)
                .padding(.horizontal, 20)
                .opacity(isTesting ? 1 : 0.2)

            gaugeScalePicker
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                AppTheme.cardFill
                RadialGradient(
                    colors: [glowColor.opacity(0.22), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 320
                )
                LinearGradient(
                    colors: [.white.opacity(0.04), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .animation(.easeInOut(duration: 0.6), value: manager.state)
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [glowColor.opacity(0.35), AppTheme.cardStroke],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .shadow(color: glowColor.opacity(0.18), radius: 24, x: 0, y: 10)
    }

    // MARK: - Live metrics row

    private var liveMetricsRow: some View {
        HStack(spacing: 0) {
            AppMetric(
                icon: "timer",
                value: manager.ping > 0 ? String(format: "%.0f", manager.ping) : "--",
                unit: "ms",
                tint: pingColor,
                caption: "Ping"
            )
            AppMetricDivider()
            AppMetric(
                icon: "arrow.down",
                value: manager.displayDownloadSpeed > 0 ? formatMbps(manager.displayDownloadSpeed) : (manager.finalDownload > 0 ? formatMbps(manager.finalDownload) : "--"),
                unit: "Mbps",
                tint: downloadColor,
                caption: "Download"
            )
            AppMetricDivider()
            AppMetric(
                icon: "arrow.up",
                value: manager.displayUploadSpeed > 0 ? formatMbps(manager.displayUploadSpeed) : (manager.finalUpload > 0 ? formatMbps(manager.finalUpload) : "--"),
                unit: "Mbps",
                tint: uploadColor,
                caption: "Upload"
            )
        }
        .padding(.vertical, 14)
        .appCard(padding: nil)
    }

    // MARK: - Control button

    private var controlButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            if isTesting {
                manager.cancelTest()
            } else {
                Task { await manager.startTest() }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isTesting ? "xmark" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(isTesting ? "Cancel" : "Start Test")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(AppPrimaryButtonStyle(colors: isTesting ? cancelGradient : AppTheme.heroGradient))
        .overlay {
            // Moving highlight sweeping across the idle button.
            if !isTesting {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.18), .clear],
                            startPoint: .init(x: shimmerPhase - 0.35, y: 0),
                            endPoint: .init(x: shimmerPhase + 0.35, y: 0)
                        )
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .scaleEffect(isTesting && animatePulse ? 1.015 : 1)
        .animation(
            isTesting ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
            value: animatePulse
        )
        .shadow(color: (isTesting ? AppTheme.danger : AppTheme.download).opacity(0.35), radius: 18, x: 0, y: 10)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.4
            }
        }
    }

    private var cancelGradient: [Color] {
        [AppTheme.danger, Color(red: 0.72, green: 0.12, blue: 0.20)]
    }

    // MARK: - Result cards

    private var resultCards: some View {
        VStack(spacing: 12) {
            // Quality score hero card
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network Quality Score")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .textCase(.uppercase)
                    Text("\(networkScore) / 100")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("puan")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 12)
                Text(networkGrade)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(gradeColor)
                    .frame(width: 76, height: 76)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .appHeroCard()

            HStack(spacing: 12) {
                resultCard(title: "Ping",     value: String(format: "%.0f", manager.ping), unit: "ms",   icon: "timer",      color: pingColor)
                resultCard(title: "Download", value: formatMbps(manager.finalDownload),     unit: "Mbps", icon: "arrow.down", color: downloadColor)
                resultCard(title: "Upload",   value: formatMbps(manager.finalUpload),       unit: "Mbps", icon: "arrow.up",   color: uploadColor)
            }
        }
    }

    private var shareCardButton: some View {
        Button {
            showShareSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                Text("Share")
            }
        }
        .buttonStyle(AppSecondaryButtonStyle())
    }

    // MARK: - Network details section

    private var networkDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                collapsibleHeader("📡 WiFi Network Details", isExpanded: $isNetworkDetailsExpanded)

                if isNetworkDetailsExpanded {
                    Button {
                        Task { await wifiInfoManager.refresh() }
                    } label: {
                        HStack(spacing: 6) {
                            if wifiInfoManager.isRefreshing {
                                ProgressView().tint(.white).scaleEffect(0.75)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Yenile")
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.download)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }

            if isNetworkDetailsExpanded {
                Group {
                    if wifiInfoManager.hasLocationPermission {
                        VStack(alignment: .leading, spacing: 18) {
                            networkDetailsGroup(title: "WiFi") {
                                detailRow(title: "SSID", value: wifiInfoManager.ssid ?? "Unknown")
                                AppRowDivider(leadingInset: 16)
                                detailRow(title: "BSSID", value: wifiInfoManager.bssid ?? "Unknown")
                                AppRowDivider(leadingInset: 16)
                                detailRow(title: "Frekans", value: wifiInfoManager.frequencyBand)
                                AppRowDivider(leadingInset: 16)
                                signalStrengthRow
                            }
                            networkDetailsGroup(title: "Address Info") {
                                detailRow(title: "IP", value: wifiInfoManager.ipAddress ?? "--")
                                AppRowDivider(leadingInset: 16)
                                detailRow(title: "Gateway", value: wifiInfoManager.routerIP ?? "--")
                                AppRowDivider(leadingInset: 16)
                                detailRow(title: "DNS", value: wifiInfoManager.dnsServers.isEmpty ? "--" : wifiInfoManager.dnsServers.joined(separator: ", "))
                                AppRowDivider(leadingInset: 16)
                                detailRow(title: "External IP", value: wifiInfoManager.externalIP ?? "--")
                                AppRowDivider(leadingInset: 16)
                                detailRow(title: "ISP", value: wifiInfoManager.ispName ?? "--")
                                AppRowDivider(leadingInset: 16)
                                detailRow(title: "NAT", value: wifiInfoManager.natType ?? "--")
                            }
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Location Permission Required", systemImage: "location.slash.fill")
                        } description: {
                            Text("Location permission is required to view SSID and BSSID information.")
                        } actions: {
                            Button("Open Settings") { wifiInfoManager.openAppSettings() }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.download)
                        }
                        .padding(.vertical, 8)
                        .appCard()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - History section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            collapsibleHeader("Past Tests", isExpanded: $isHistoryExpanded)

            if isHistoryExpanded {
                VStack(spacing: 0) {
                    if manager.history.isEmpty {
                        AppEmptyState(icon: "clock.arrow.circlepath", title: "No recorded speed tests yet.")
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(manager.history) { result in
                                historyRow(result)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { delete(result) } label: {
                                            Label("Sil", systemImage: "trash.fill")
                                        }
                                    }

                                if result.id != manager.history.last?.id {
                                    AppRowDivider()
                                }
                            }
                        }

                        AppRowDivider(leadingInset: 0)

                        Button {
                            manager.clearHistory()
                        } label: {
                            Text("Clear History")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(AppRowButtonStyle())
                    }
                }
                .appCard(padding: nil)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func historyRow(_ result: SpeedTestResult) -> some View {
        HStack(spacing: 14) {
            AppIconTile(systemName: "gauge.with.dots.needle.67percent", tint: downloadColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                HStack(spacing: 10) {
                    historyMetric(systemImage: "arrow.down", value: formatMbps(result.downloadSpeed), unit: "Mbps", color: downloadColor)
                    historyMetric(systemImage: "arrow.up",   value: formatMbps(result.uploadSpeed),   unit: "Mbps", color: uploadColor)
                    historyMetric(systemImage: "timer",      value: String(format: "%.0f", result.ping), unit: "ms", color: pingColor)
                }
            }

            Spacer(minLength: 8)

            let grade = gradeFor(result)
            let color = gradeColorFor(result)
            Text(grade)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Small helpers (views)

    /// Uppercase section header that toggles its section open/closed.
    private func collapsibleHeader(_ title: LocalizedStringKey, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                AppSectionHeader(title)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func resultCard(title: LocalizedStringKey, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppIconTile(systemName: icon, tint: color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
        .appCard(padding: 14)
    }

    private func historyMetric(systemImage: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.82))
            Text(unit)
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
    }

    private func delete(_ result: SpeedTestResult) {
        if let index = manager.history.firstIndex(where: { $0.id == result.id }) {
            manager.deleteHistory(at: IndexSet(integer: index))
        }
    }

    // MARK: - Computed properties

    private var currentSpeedMbps: Double {
        switch manager.state {
        case .downloadTesting: return mbps(manager.displayDownloadSpeed)
        case .transitionToUpload: return 0
        case .uploadTesting:   return mbps(manager.displayUploadSpeed)
        case .finished:        return mbps(max(manager.finalDownload, manager.finalUpload))
        default:               return 0
        }
    }

    private var formattedCurrentSpeed: (value: String, unit: String) {
        (String(format: "%.1f", currentSpeedMbps), "Mbps")
    }

    private var glowColor: Color {
        switch manager.state {
        case .pingTesting:        return pingColor
        case .downloadTesting:    return downloadColor
        case .transitionToUpload: return downloadColor
        case .uploadTesting:      return uploadColor
        case .finished:           return downloadColor
        default:                  return pingColor
        }
    }

    private var gaugeSubtitle: String {
        switch manager.state {
        case .idle:               return "Ready"
        case .pingTesting:        return "Measuring Ping..."
        case .downloadTesting:    return "Download Test..."
        case .transitionToUpload: return "Preparing Upload..."
        case .uploadTesting:      return "Upload Test..."
        case .finished:           return "Test Completed"
        case .failed:             return "Test Failed"
        }
    }

    private var isTesting: Bool {
        manager.state == .pingTesting ||
        manager.state == .downloadTesting ||
        manager.state == .transitionToUpload ||
        manager.state == .uploadTesting
    }

    private var currentPhase: PhaseStepperView.Phase? {
        switch manager.state {
        case .idle:               return nil
        case .pingTesting:        return .ping
        case .downloadTesting:    return .download
        case .transitionToUpload: return .download
        case .uploadTesting:      return .upload
        case .finished:           return nil
        case .failed:             return nil
        }
    }

    private var networkScore: Int {
        var score = 0
        if manager.ping < 20  { score += 30 } else if manager.ping < 50  { score += 18 } else if manager.ping < 100 { score += 8 }
        let dl = mbps(manager.finalDownload)
        if dl > 100 { score += 40 } else if dl > 50 { score += 28 } else if dl > 20 { score += 16 } else if dl > 5 { score += 8 }
        let ul = mbps(manager.finalUpload)
        if ul > 50  { score += 30 } else if ul > 25  { score += 20 } else if ul > 10 { score += 12 } else if ul > 2 { score += 6 }
        return min(score, 100)
    }

    private var networkGrade: String { gradeForScore(networkScore) }
    private var gradeColor: Color    { gradeColorForScore(networkScore) }

    private func gradeFor(_ result: SpeedTestResult) -> String {
        var score = 0
        if result.ping < 20 { score += 30 } else if result.ping < 50 { score += 18 } else if result.ping < 100 { score += 8 }
        let dl = mbps(result.downloadSpeed)
        if dl > 100 { score += 40 } else if dl > 50 { score += 28 } else if dl > 20 { score += 16 } else if dl > 5 { score += 8 }
        let ul = mbps(result.uploadSpeed)
        if ul > 50 { score += 30 } else if ul > 25 { score += 20 } else if ul > 10 { score += 12 } else if ul > 2 { score += 6 }
        return gradeForScore(min(score, 100))
    }
    private func gradeColorFor(_ result: SpeedTestResult) -> Color {
        var score = 0
        if result.ping < 20 { score += 30 } else if result.ping < 50 { score += 18 } else if result.ping < 100 { score += 8 }
        let dl = mbps(result.downloadSpeed)
        if dl > 100 { score += 40 } else if dl > 50 { score += 28 } else if dl > 20 { score += 16 } else if dl > 5 { score += 8 }
        let ul = mbps(result.uploadSpeed)
        if ul > 50 { score += 30 } else if ul > 25 { score += 20 } else if ul > 10 { score += 12 } else if ul > 2 { score += 6 }
        return gradeColorForScore(min(score, 100))
    }

    private func gradeForScore(_ s: Int) -> String {
        if s >= 90 { return "A" } else if s >= 75 { return "B" } else if s >= 55 { return "C" } else if s >= 35 { return "D" } else { return "F" }
    }
    private func gradeColorForScore(_ s: Int) -> Color {
        switch gradeForScore(s) {
        case "A": return .green
        case "B": return Color(red: 132/255, green: 204/255, blue: 22/255)
        case "C": return .yellow
        case "D": return .orange
        default:  return .red
        }
    }

    /// Manager values are bytes/second; network speeds are shown in megabits/second.
    private func mbps(_ bytesPerSecond: Double) -> Double {
        bytesPerSecond * 8 / 1_000_000
    }

    private func formatMbps(_ bytesPerSecond: Double) -> String {
        String(format: "%.1f", mbps(bytesPerSecond))
    }

    private func updateNeedle() {
        let progress = min(1, currentSpeedMbps / gaugeMaxSpeed)
        withAnimation(.interpolatingSpring(stiffness: 40, damping: 10, initialVelocity: 2)) {
            needleProgress = progress
        }
    }

    // MARK: WiFi row helpers

    private var signalStrengthRow: some View {
        HStack(spacing: 12) {
            Text("Signal Strength")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 8)
            WiFiStrengthIcon(color: wifiInfoManager.signalStrength.color, level: signalBarLevel)
            VStack(alignment: .trailing, spacing: 2) {
                Text(wifiInfoManager.signalStrength.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(wifiInfoManager.rssi) dBm")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(wifiInfoManager.signalStrength.color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func networkDetailsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.tertiaryText)
                .textCase(.uppercase)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .appCard(padding: nil)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var signalBarLevel: Int {
        switch wifiInfoManager.signalStrength {
        case .excellent: return 4
        case .good:      return 3
        case .fair:      return 2
        case .poor:      return 1
        }
    }
}

// MARK: - WiFiStrengthIcon

private struct WiFiStrengthIcon: View {
    let color: Color
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Image(systemName: "wifi")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index < level ? color : Color.white.opacity(0.14))
                        .frame(width: 5, height: CGFloat(8 + index * 5))
                }
            }
        }
    }
}

#Preview {
    SpeedTestView(manager: SpeedTestManager())
        .preferredColorScheme(.dark)
}
