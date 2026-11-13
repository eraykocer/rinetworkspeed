//
//  SpeedTestView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import UIKit
import StoreKit

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
                // ── 2. Background track arc (grey, via trim — no artifacts) ──
                Circle()
                    .trim(from: 0, to: Self.trackFrac)
                    .stroke(AppTheme.ink.opacity(0.12),
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
                    .fill(AppTheme.ink)
                    .frame(width: side * 0.017, height: needleL)
                    .shadow(color: AppTheme.ink.opacity(0.42), radius: 4)
                    .rotationEffect(.degrees(needleRot), anchor: .bottom)
                    .offset(y: -needleL / 2)

                // ── 6. Centre hub ─────────────────────────────────────
                Circle()
                    .fill(AppTheme.ink.opacity(0.9))
                    .frame(width: hubSz)
                    .shadow(color: AppTheme.ink.opacity(0.40), radius: 5)

                // ── 7. Speed value text ───────────────────────────────
                VStack(spacing: 1) {
                    Text(valueText)
                        .font(.system(size: side * 0.115, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .contentTransition(.numericText())
                    Text(unitText)
                        .font(.system(size: side * 0.042, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink.opacity(0.65))
                    Text(subtitle)
                        .font(.system(size: side * 0.036, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.ink.opacity(0.42))
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
                    ctx.stroke(path, with: .color(AppTheme.ink.opacity(0.70)), lineWidth: 2)

                    let label = value >= 1000 ? "\(Int(value / 1000))k" : "\(Int(value))"
                    ctx.draw(
                        Text(label)
                            .font(.system(size: s * 0.033, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.ink.opacity(0.65)),
                        at: point(for: value, radius: radius + s * 0.074)
                    )
                } else {
                    path.move(to: point(for: value, radius: radius - s * 0.005))
                    path.addLine(to: point(for: value, radius: radius - s * 0.026))
                    ctx.stroke(path, with: .color(AppTheme.ink.opacity(0.20)), lineWidth: 1)
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
        case .ping:     return String(localized: "Ping")
        case .download: return String(localized: "Download")
        case .upload:   return String(localized: "Upload")
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
                            .fill(isDone ? color(for: phase) : AppTheme.ink.opacity(0.06))
                            .frame(width: 26, height: 26)
                            .scaleEffect(isActive && pulse ? 1.18 : 1)
                            .animation(
                                isActive ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default,
                                value: pulse
                            )
                        if isDone {
                            Image(systemName: "checkmark")
                                .appFont(size: 11, weight: .bold)
                                .foregroundStyle(AppTheme.ink)
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
                    Text(label(for: phase).uppercased(with: .current))
                        .appFont(size: 10, weight: .bold, design: .rounded)
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
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.requestReview) private var requestReview
    @StateObject private var wifiInfoManager = WiFiInfoManager()
    @State private var animatePulse = false
    @State private var isNetworkDetailsExpanded = false
    @State private var isHistoryExpanded = true
    @State private var showShareSheet = false
    @State private var needleProgress: Double = 0
    private let recentHistoryCount = 5
    #if DEBUG
    // Screenshot / UI review helper: launch with `-debugShowHistory YES`.
    @State private var showingHistory = UserDefaults.standard.bool(forKey: "debugShowHistory")
    #else
    @State private var showingHistory = false
    #endif

    private let pingColor     = AppTheme.ping
    private let downloadColor = AppTheme.download
    private let uploadColor   = AppTheme.upload
    /// Full-scale value of the speedometer in Mbps; user-selectable (250 / 500 / 1k).
    @AppStorage("gaugeMaxSpeed") private var gaugeMaxSpeed: Double = 1_000
    private let gaugeScaleOptions: [Double] = [250, 500, 1_000]

    /// False when pushed onto an existing NavigationStack (Tools tab);
    /// nesting a second stack there breaks navigation.
    var embedsInNavigationStack = true

    var body: some View {
        Group {
            if embedsInNavigationStack {
                NavigationStack { page }
            } else {
                page
            }
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
        .onChange(of: isNetworkDetailsExpanded) { _, isExpanded in
            // First time the details are opened is when location access makes sense to ask for.
            if isExpanded { wifiInfoManager.requestLocationIfNeeded() }
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
                askForReviewIfAppropriate()
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

    private var page: some View {
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
        .navigationDestination(isPresented: $showingHistory) {
            SpeedTestHistoryView(manager: manager)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Current speed"))
            .accessibilityValue(Text(verbatim: "\(formattedCurrentSpeed.value) \(formattedCurrentSpeed.unit), \(gaugeSubtitle)"))
            .accessibilityAddTraits(.updatesFrequently)

            // Wave line
            SpeedWaveView(amplitude: needleProgress, color: glowColor)
                .frame(height: 36)
                .padding(.horizontal, 20)
                .opacity(isTesting ? 1 : 0.2)
                .accessibilityHidden(true)

            gaugeScalePicker
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
                .stroke(glowColor.opacity(0.35), lineWidth: 1)
                .animation(.easeInOut(duration: 0.6), value: manager.state)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .shadow(color: glowColor.opacity(0.18), radius: 24, x: 0, y: 10)
    }

    // MARK: - Live metrics row

    private var liveMetricsRow: some View {
        HStack(spacing: 0) {
            AppMetric(
                icon: "timer",
                value: manager.ping > 0 ? manager.ping.fixed(0) : "--",
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
                    .appFont(size: 15, weight: .bold)
                Text(isTesting ? "Cancel" : "Start Test")
                    .appFont(size: 18, weight: .bold, design: .rounded)
                    .lineLimit(1)
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(AppPrimaryButtonStyle(tint: isTesting ? AppTheme.danger : AppTheme.accent))
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppTheme.ink.opacity(0.16), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .scaleEffect(isTesting && animatePulse ? 1.015 : 1)
        .animation(
            isTesting ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
            value: animatePulse
        )
        .shadow(color: (isTesting ? AppTheme.danger : AppTheme.accent).opacity(0.35), radius: 18, x: 0, y: 10)
    }

    // MARK: - Result cards

    private var resultCards: some View {
        VStack(spacing: 12) {
            // Quality score hero card
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network Quality Score")
                        .appFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundStyle(AppTheme.ink.opacity(0.75))
                        .textCase(.uppercase)
                    Text("\(currentScore.value) / 100")
                        .appFont(size: 30, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.ink)
                        .contentTransition(.numericText())
                    Text(currentScore.verdict)
                        .appFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AppTheme.ink.opacity(0.65))
                }
                Spacer(minLength: 12)
                Text(currentScore.grade)
                    .appFont(size: 44, weight: .black, design: .rounded)
                    .foregroundStyle(currentScore.gradeColor)
                    .frame(width: 76, height: 76)
                    .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .accessibilityLabel(Text("Grade \(currentScore.grade)"))
            }
            .appHeroCard()
            .accessibilityElement(children: .combine)

            AppAdaptiveStack(spacing: 12) {
                resultCard(title: "Ping",     value: manager.ping.fixed(0), unit: "ms",   icon: "timer",      color: pingColor)
                resultCard(title: "Download", value: formatMbps(manager.finalDownload),     unit: "Mbps", icon: "arrow.down", color: downloadColor)
                resultCard(title: "Upload",   value: formatMbps(manager.finalUpload),       unit: "Mbps", icon: "arrow.up",   color: uploadColor)
            }

            useCaseSection
        }
    }

    /// Plain-language answer to "what can I do with this connection?".
    private var useCaseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("Good For")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(currentScore.useCases) { useCase in
                    HStack(spacing: 8) {
                        Image(systemName: useCase.isSupported ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(useCase.isSupported ? AppTheme.ping : AppTheme.danger)
                        Image(systemName: useCase.icon)
                            .foregroundStyle(AppTheme.secondaryText)
                            .accessibilityHidden(true)
                        Text(useCase.title)
                            .foregroundStyle(useCase.isSupported ? AppTheme.primaryText : AppTheme.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .appFont(size: 14, weight: .semibold, design: .rounded)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.cardStroke, lineWidth: 1)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(useCase.title))
                    .accessibilityValue(useCase.isSupported ? Text("Supported") : Text("Not recommended"))
                }
            }
        }
    }

    private var shareCardButton: some View {
        Button {
            showShareSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .appFont(size: 15, weight: .semibold)
                Text("Share")
            }
        }
        .buttonStyle(AppSecondaryButtonStyle())
    }

    // MARK: - Network details section

    private var networkDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                collapsibleHeader("Wi-Fi Network Details", isExpanded: $isNetworkDetailsExpanded)

                if isNetworkDetailsExpanded {
                    Button {
                        Task { await wifiInfoManager.refresh() }
                    } label: {
                        HStack(spacing: 6) {
                            if wifiInfoManager.isRefreshing {
                                ProgressView().tint(AppTheme.ink).scaleEffect(0.75)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh")
                        }
                        .appFont(size: 13, weight: .semibold, design: .rounded)
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
                                detailRow(title: "Security", value: wifiInfoManager.securityType ?? "Unknown")
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
                            Text("iOS only shares the Wi-Fi network name and details with apps that have location access. Your location is not stored or sent anywhere.")
                        } actions: {
                            if wifiInfoManager.canRequestLocation {
                                Button("Allow Location Access") { wifiInfoManager.requestLocationIfNeeded() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(AppTheme.accent)
                            } else {
                                Button("Open Settings") { wifiInfoManager.openAppSettings() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(AppTheme.accent)
                            }
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
                        let recent = Array(manager.history.prefix(recentHistoryCount))
                        ForEach(recent) { result in
                            SpeedTestHistoryRow(result: result)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        manager.deleteHistory(ids: [result.id])
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            AppRowDivider(leadingInset: 0)
                        }

                        NavigationLink {
                            SpeedTestHistoryView(manager: manager)
                        } label: {
                            AppRow(
                                icon: "chart.line.uptrend.xyaxis",
                                tint: AppTheme.accent,
                                title: "See All Tests",
                                subtitle: "Trend, averages and filters"
                            ) {
                                HStack(spacing: 8) {
                                    if purchaseManager.isPro {
                                        Text(verbatim: "\(manager.history.count)")
                                            .appFont(size: 15, weight: .semibold, design: .rounded)
                                            .monospacedDigit()
                                            .foregroundStyle(AppTheme.secondaryText)
                                    } else {
                                        ProBadge()
                                    }
                                    AppChevron()
                                }
                            }
                        }
                        .buttonStyle(AppRowButtonStyle())
                        // Free users see their latest tests here; the full history is Pro.
                        .proGated(feature: .unlimitedHistory)
                    }
                }
                .appCard(padding: nil)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
                    .appFont(size: 12, weight: .semibold)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded.wrappedValue ? Text("Expanded") : Text("Collapsed"))
    }

    private func resultCard(title: LocalizedStringKey, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppIconTile(systemName: icon, tint: color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .appFont(size: 20, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(unit)
                        .appFont(size: 10, weight: .semibold, design: .rounded)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
        .appCard(padding: 14)
        .accessibilityElement(children: .combine)
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
        (currentSpeedMbps.fixed(1), "Mbps")
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
        case .idle:               return String(localized: "Ready")
        case .pingTesting:        return String(localized: "Measuring Ping…")
        case .downloadTesting:    return String(localized: "Testing Download…")
        case .transitionToUpload: return String(localized: "Preparing Upload…")
        case .uploadTesting:      return String(localized: "Testing Upload…")
        case .finished:           return String(localized: "Test Completed")
        case .failed:             return String(localized: "Test Failed")
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

    /// After a good result, occasionally ask for an App Store rating (see `ReviewPromptPolicy`).
    private func askForReviewIfAppropriate() {
        let policy = ReviewPromptStore.policy()
        guard policy.shouldPrompt(afterScore: currentScore.value, currentVersion: ReviewPromptStore.currentVersion) else { return }
        ReviewPromptStore.recordPrompt()
        Task {
            // Let the result cards appear first.
            try? await Task.sleep(for: .seconds(2))
            requestReview()
        }
    }

    private var currentScore: SpeedTestScore {
        SpeedTestScore(
            downloadBytesPerSecond: manager.finalDownload,
            uploadBytesPerSecond: manager.finalUpload,
            ping: manager.ping,
            jitter: manager.jitter
        )
    }

    /// Manager values are bytes/second; network speeds are shown in megabits/second.
    private func mbps(_ bytesPerSecond: Double) -> Double {
        bytesPerSecond * 8 / 1_000_000
    }

    private func formatMbps(_ bytesPerSecond: Double) -> String {
        (mbps(bytesPerSecond)).fixed(1)
    }

    private func updateNeedle() {
        let progress = min(1, currentSpeedMbps / gaugeMaxSpeed)
        withAnimation(.interpolatingSpring(stiffness: 40, damping: 10, initialVelocity: 2)) {
            needleProgress = progress
        }
    }

    // MARK: WiFi row helpers

    private func networkDetailsGroup<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(AppTheme.tertiaryText)
                .textCase(.uppercase)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .appCard(padding: nil)
        }
    }

    private func detailRow(title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .appFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .appFont(size: 14, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    SpeedTestView(manager: SpeedTestManager())
        .preferredColorScheme(.dark)
}
