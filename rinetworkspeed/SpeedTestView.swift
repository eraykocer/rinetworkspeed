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
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                let amp = amplitude * 22
                let freq = 2.0 * Double.pi / size.width
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                for x in stride(from: 0, through: size.width, by: 1) {
                    let y = size.height / 2 + amp * sin(freq * x * 2.5 + phase)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                ctx.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 2)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                phase = 2 * Double.pi
            }
        }
    }
}

// MARK: - PhaseStepperView

private struct PhaseStepperView: View {
    enum Phase: Int { case ping = 0, download = 1, upload = 2 }
    let current: Phase?          // nil = idle / done

    private let pingColor    = Color(red: 168/255, green: 85/255,  blue: 247/255)
    private let downloadColor = Color(red: 59/255,  green: 130/255, blue: 246/255)
    private let uploadColor  = Color(red: 249/255, green: 115/255, blue: 22/255)

    private func color(for phase: Phase) -> Color {
        switch phase {
        case .ping:     return pingColor
        case .download: return downloadColor
        case .upload:   return uploadColor
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
                            .fill(isDone ? color(for: phase) : Color.white.opacity(0.08))
                            .frame(width: 28, height: 28)
                            .scaleEffect(isActive && pulse ? 1.18 : 1)
                            .animation(
                                isActive ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default,
                                value: pulse
                            )
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle()
                                .stroke(
                                    isActive ? color(for: phase) : Color.white.opacity(0.2),
                                    lineWidth: 2
                                )
                                .frame(width: 28, height: 28)
                            if isActive {
                                Circle()
                                    .fill(color(for: phase).opacity(0.35))
                                    .frame(width: 14, height: 14)
                            }
                        }
                    }
                    Text(label(for: phase))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            isActive  ? color(for: phase) :
                            isDone    ? .white.opacity(0.75) :
                                        .white.opacity(0.3)
                        )
                }

                if phase != .upload {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 22)
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

    private let backgroundColor = Color(red: 10/255, green: 10/255, blue: 10/255)
    private let pingColor    = Color(red: 168/255, green: 85/255,  blue: 247/255)
    private let downloadColor = Color(red: 59/255,  green: 130/255, blue: 246/255)
    private let uploadColor  = Color(red: 249/255, green: 115/255, blue: 22/255)
    private let gaugeMaxSpeed: Double = 1_000

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // ── Speedometer ──────────────────────────────────────
                    speedometerSection

                    // ── Phase stepper (only while testing) ──────────────
                    if isTesting || manager.state == .finished {
                        PhaseStepperView(current: currentPhase)
                            .padding(.horizontal, 24)
                            .transition(.opacity.combined(with: .scale))
                    }

                    // ── Live metrics row ─────────────────────────────────
                    if isTesting || manager.state == .finished {
                        liveMetricsRow
                    }

                    // ── Result cards (after test) ────────────────────────
                    if manager.state == .finished {
                        resultCards
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        shareCardButton
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // ── Control button ───────────────────────────────────
                    controlButton

                    // ── History ──────────────────────────────────────────
                    historySection

                    // ── WiFi Details ─────────────────────────────────────
                    if manager.state == .finished {
                        networkDetailsSection
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: manager.state)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Speed Test")
        }
        .background(backgroundColor.ignoresSafeArea())
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

    private var speedometerSection: some View {
        ZStack {
            // Glow behind gauge
            Circle()
                .fill(glowColor.opacity(0.07))
                .blur(radius: 40)
                .frame(width: 280, height: 280)

            VStack(spacing: 8) {
                SpeedometerView(
                    progress: needleProgress,
                    maxSpeed: gaugeMaxSpeed,
                    valueText: formattedCurrentSpeed.value,
                    unitText: formattedCurrentSpeed.unit,
                    subtitle: gaugeSubtitle,
                    glowColor: glowColor
                )
                .frame(height: UIScreen.main.bounds.width * 0.85)

                // Wave line
                SpeedWaveView(amplitude: needleProgress, color: glowColor)
                    .frame(height: 36)
                    .padding(.horizontal, 30)
                    .opacity(isTesting ? 1 : 0.2)
            }
        }
    }

    // MARK: - Live metrics row

    private var liveMetricsRow: some View {
        HStack(spacing: 0) {
            liveMetricCell(
                label: "Ping",
                value: manager.ping > 0 ? String(format: "%.0f", manager.ping) : "--",
                unit: "ms",
                color: pingColor
            )
            Divider()
                .frame(height: 36)
                .background(Color.white.opacity(0.08))
            liveMetricCell(
                label: "Download",
                value: manager.displayDownloadSpeed > 0 ? formatMbps(manager.displayDownloadSpeed) : (manager.finalDownload > 0 ? formatMbps(manager.finalDownload) : "--"),
                unit: "Mbps",
                color: downloadColor
            )
            Divider()
                .frame(height: 36)
                .background(Color.white.opacity(0.08))
            liveMetricCell(
                label: "Upload",
                value: manager.displayUploadSpeed > 0 ? formatMbps(manager.displayUploadSpeed) : (manager.finalUpload > 0 ? formatMbps(manager.finalUpload) : "--"),
                unit: "Mbps",
                color: uploadColor
            )
        }
        .padding(.vertical, 14)
        .speedTestCardStyle()
    }

    private func liveMetricCell(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
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
            ZStack {
                if !isTesting {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 19/255, green: 41/255, blue: 79/255),
                                    Color(red: 22/255, green: 63/255, blue: 126/255),
                                    Color(red: 15/255, green: 102/255, blue: 170/255)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.22),
                                    .clear,
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(1)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.14), .clear],
                                startPoint: .init(x: shimmerPhase - 0.35, y: 0),
                                endPoint: .init(x: shimmerPhase + 0.35, y: 0)
                            )
                        )
                        .blendMode(.screen)
                        .clipped()
                } else {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 127/255, green: 29/255, blue: 29/255),
                                    Color(red: 185/255, green: 28/255, blue: 28/255),
                                    Color(red: 239/255, green: 68/255, blue: 68/255)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(animatePulse ? 1.015 : 1)
                        .animation(
                            .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                            value: animatePulse
                        )
                }
                Text(isTesting ? "Cancel" : "Start Test")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(isTesting ? 0.14 : 0.18), lineWidth: 1)
            )
            .shadow(color: (isTesting ? Color.red : Color(red: 15/255, green: 102/255, blue: 170/255)).opacity(0.35), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.4
            }
        }
    }

    // MARK: - Result cards

    private var resultCards: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                resultCard(title: "Ping",      value: String(format: "%.0f", manager.ping),    unit: "ms",   icon: "timer",               color: pingColor)
                resultCard(title: "Download",   value: formatMbps(manager.finalDownload),        unit: "Mbps", icon: "arrow.down.circle.fill", color: downloadColor)
                resultCard(title: "Upload",   value: formatMbps(manager.finalUpload),          unit: "Mbps", icon: "arrow.up.circle.fill",   color: uploadColor)
            }

            // Quality score card
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Network Quality Score")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(networkGrade)
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(gradeColor)
                        .shadow(color: gradeColor.opacity(0.55), radius: 12)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(networkScore) / 100")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("puan")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .speedTestCardStyle()
        }
    }

    private var shareCardButton: some View {
        Button {
            showShareSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                Text("Share")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 22/255, green: 26/255, blue: 36/255),
                                Color(red: 32/255, green: 39/255, blue: 57/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.12), .clear, .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.18), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Network details section

    private var networkDetailsSection: some View {
        DisclosureGroup(isExpanded: $isNetworkDetailsExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button {
                        Task { await wifiInfoManager.refresh() }
                    } label: {
                        HStack(spacing: 6) {
                            if wifiInfoManager.isRefreshing {
                                ProgressView().tint(.white).scaleEffect(0.85)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Yenile")
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                    }
                    .buttonStyle(.plain)
                }

                if wifiInfoManager.hasLocationPermission {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14, alignment: .top),
                            GridItem(.flexible(), spacing: 14, alignment: .top)
                        ],
                        alignment: .leading,
                        spacing: 14
                    ) {
                        networkDetailsColumn(title: "WiFi") {
                            detailTile(title: "SSID", value: wifiInfoManager.ssid ?? "Unknown")
                            detailTile(title: "BSSID", value: wifiInfoManager.bssid ?? "Unknown")
                            detailTile(title: "Frekans", value: wifiInfoManager.frequencyBand)
                            signalStrengthTile
                        }
                        networkDetailsColumn(title: "Address Info") {
                            detailTile(title: "IP", value: wifiInfoManager.ipAddress ?? "--")
                            detailTile(title: "Gateway", value: wifiInfoManager.routerIP ?? "--")
                            detailTile(title: "DNS", value: wifiInfoManager.dnsServers.isEmpty ? "--" : wifiInfoManager.dnsServers.joined(separator: ", "))
                            detailTile(title: "External IP", value: wifiInfoManager.externalIP ?? "--")
                            detailTile(title: "ISP", value: wifiInfoManager.ispName ?? "--")
                            detailTile(title: "NAT", value: wifiInfoManager.natType ?? "--")
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
                    }
                    .padding(.top, 14)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wifi")
                    .foregroundStyle(downloadColor)
                Text("📡 WiFi Network Details")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .tint(.white)
        .padding(18)
        .speedTestCardStyle()
    }

    // MARK: - History section

    private var historySection: some View {
        DisclosureGroup(isExpanded: $isHistoryExpanded) {
            VStack(spacing: 10) {
                if manager.history.isEmpty {
                    Text("No recorded speed tests yet.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(manager.history) { result in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                    HStack(spacing: 10) {
                                        historyMetric(systemImage: "arrow.down.circle.fill", value: formatMbps(result.downloadSpeed), unit: "Mbps", color: downloadColor)
                                        historyMetric(systemImage: "arrow.up.circle.fill",   value: formatMbps(result.uploadSpeed),   unit: "Mbps", color: uploadColor)
                                        historyMetric(systemImage: "timer",                   value: String(format: "%.0f", result.ping), unit: "ms", color: pingColor)
                                    }
                                }
                                Spacer()
                                Text(gradeFor(result))
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .foregroundStyle(gradeColorFor(result))
                                    .shadow(color: gradeColorFor(result).opacity(0.5), radius: 6)
                            }
                            .padding(14)
                            .speedTestCardStyle()
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(result) } label: {
                                    Label("Sil", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                if !manager.history.isEmpty {
                    Button("Clear History") { manager.clearHistory() }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(downloadColor)
                Text("Past Tests")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .tint(.white)
        .padding(18)
        .speedTestCardStyle()
    }

    // MARK: - Small helpers (views)

    private func resultCard(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .speedTestCardStyle()
    }

    private func historyMetric(systemImage: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .foregroundStyle(.white.opacity(0.82))
            Text(unit)
                .foregroundStyle(.white.opacity(0.45))
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
    }

    private func delete(_ result: SpeedTestResult) {
        if let index = manager.history.firstIndex(where: { $0.id == result.id }) {
            manager.deleteHistory(at: IndexSet(integer: index))
        }
    }

    // MARK: - Computed properties

    private var currentSpeedMbps: Double {
        switch manager.state {
        case .downloadTesting: return manager.displayDownloadSpeed / 1_000_000
        case .transitionToUpload: return 0
        case .uploadTesting:   return manager.displayUploadSpeed   / 1_000_000
        case .finished:        return max(manager.finalDownload, manager.finalUpload) / 1_000_000
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
        let dl = manager.finalDownload / 1_000_000
        if dl > 100 { score += 40 } else if dl > 50 { score += 28 } else if dl > 20 { score += 16 } else if dl > 5 { score += 8 }
        let ul = manager.finalUpload / 1_000_000
        if ul > 50  { score += 30 } else if ul > 25  { score += 20 } else if ul > 10 { score += 12 } else if ul > 2 { score += 6 }
        return min(score, 100)
    }

    private var networkGrade: String { gradeForScore(networkScore) }
    private var gradeColor: Color    { gradeColorForScore(networkScore) }

    private func gradeFor(_ result: SpeedTestResult) -> String {
        var score = 0
        if result.ping < 20 { score += 30 } else if result.ping < 50 { score += 18 } else if result.ping < 100 { score += 8 }
        let dl = result.downloadSpeed / 1_000_000
        if dl > 100 { score += 40 } else if dl > 50 { score += 28 } else if dl > 20 { score += 16 } else if dl > 5 { score += 8 }
        let ul = result.uploadSpeed / 1_000_000
        if ul > 50 { score += 30 } else if ul > 25 { score += 20 } else if ul > 10 { score += 12 } else if ul > 2 { score += 6 }
        return gradeForScore(min(score, 100))
    }
    private func gradeColorFor(_ result: SpeedTestResult) -> Color {
        var score = 0
        if result.ping < 20 { score += 30 } else if result.ping < 50 { score += 18 } else if result.ping < 100 { score += 8 }
        let dl = result.downloadSpeed / 1_000_000
        if dl > 100 { score += 40 } else if dl > 50 { score += 28 } else if dl > 20 { score += 16 } else if dl > 5 { score += 8 }
        let ul = result.uploadSpeed / 1_000_000
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

    private func formatMbps(_ bytesPerSecond: Double) -> String {
        String(format: "%.1f", bytesPerSecond / 1_000_000)
    }

    private func updateNeedle() {
        let progress = min(1, currentSpeedMbps / gaugeMaxSpeed)
        withAnimation(.interpolatingSpring(stiffness: 40, damping: 10, initialVelocity: 2)) {
            needleProgress = progress
        }
    }

    // MARK: WiFi tile helpers

    private var signalStrengthTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Signal Strength")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 10) {
                WiFiStrengthIcon(color: wifiInfoManager.signalStrength.color, level: signalBarLevel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(wifiInfoManager.signalStrength.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(wifiInfoManager.rssi) dBm")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(wifiInfoManager.signalStrength.color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func networkDetailsColumn<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func detailTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
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

// MARK: - Card modifier

private struct SpeedTestCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 6)
    }
}

private extension View {
    func speedTestCardStyle() -> some View { modifier(SpeedTestCardModifier()) }
}

#Preview {
    SpeedTestView(manager: SpeedTestManager())
}
