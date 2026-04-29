//
//  OnboardingView.swift
//  rinetworkspeed
//

import SwiftUI
import Combine
import UserNotifications
import CoreLocation

// MARK: - Main Onboarding Shell

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var currentPage: Int = 0
    @State private var fakeDownload: Double = 47.3
    @State private var fakeUpload: Double = 11.8
    @State private var speedTimer: Timer?

    private let totalPages = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ── Five pages ──────────────────────────────────────────────
            TabView(selection: $currentPage) {
                OnboardingWelcomePage()
                    .tag(0)

                OnboardingSpeedPage(download: $fakeDownload, upload: $fakeUpload)
                    .tag(1)

                OnboardingWidgetPage()
                    .tag(2)

                OnboardingNotificationPage(onNext: goToNext)
                    .tag(3)

                OnboardingLocationPage(onComplete: completeOnboarding)
                    .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // ── Controls overlay ─────────────────────────────────────────
            VStack(spacing: 0) {
                // Skip button – top right
                HStack {
                    Spacer()
                    Button("Atla") { completeOnboarding() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 60)
                        .padding(.trailing, 28)
                }

                Spacer()

                VStack(spacing: 20) {
                    // Animated dot indicator
                    HStack(spacing: 7) {
                        ForEach(0..<totalPages, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage ? Color.white : Color.white.opacity(0.28))
                                .frame(width: i == currentPage ? 22 : 7, height: 7)
                                .animation(
                                    .spring(response: 0.35, dampingFraction: 0.72),
                                    value: currentPage
                                )
                        }
                    }

                    // İleri / Başlayalım
                    HStack {
                        Spacer()
                        Button(action: handleNext) {
                            HStack(spacing: 7) {
                                Text(currentPage == totalPages - 1 ? "Let's Start" : "Next")
                                    .font(.system(size: 16, weight: .semibold))
                                Image(
                                    systemName: currentPage == totalPages - 1
                                        ? "checkmark" : "arrow.right"
                                )
                                .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .shadow(color: .white.opacity(0.2), radius: 14, x: 0, y: 5)
                        }
                        .padding(.trailing, 28)
                    }
                }
                .padding(.bottom, 52)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { startSpeedAnimation() }
        .onDisappear { speedTimer?.invalidate() }
    }

    // MARK: Actions

    private func handleNext() {
        if currentPage < totalPages - 1 {
            goToNext()
        } else {
            completeOnboarding()
        }
    }

    private func goToNext() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
            currentPage = min(currentPage + 1, totalPages - 1)
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    private func startSpeedAnimation() {
        fakeDownload = (Double.random(in: 15...120) * 10).rounded() / 10
        fakeUpload = (Double.random(in: 3...35) * 10).rounded() / 10
        speedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.38)) {
                self.fakeDownload = (Double.random(in: 15...120) * 10).rounded() / 10
                self.fakeUpload = (Double.random(in: 3...35) * 10).rounded() / 10
            }
        }
    }
}

// MARK: - Page 1 · Welcome

struct OnboardingWelcomePage: View {
    @State private var appeared = false
    @State private var iconBounce = false

    var body: some View {
        ZStack {
            meshBackground
            VStack(spacing: 36) {
                Spacer()

                // ── App icon with pulse rings ────────────────────────────
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(
                                Color.blue.opacity(0.25 - Double(i) * 0.06),
                                lineWidth: 1.5
                            )
                            .frame(
                                width: 100 + CGFloat(i * 30),
                                height: 100 + CGFloat(i * 30)
                            )
                            .scaleEffect(appeared ? 1.25 : 0.85)
                            .opacity(appeared ? 0 : 0.9)
                            .animation(
                                .easeOut(duration: 1.8)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.5),
                                value: appeared
                            )
                    }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.18, green: 0.42, blue: 1.0),
                                    Color(red: 0.52, green: 0.12, blue: 0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                        .shadow(color: .blue.opacity(0.7), radius: 24, x: 0, y: 8)

                    Image(systemName: "wifi")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: iconBounce)
                }
                .scaleEffect(appeared ? 1.0 : 0.78)
                .animation(
                    .spring(response: 0.65, dampingFraction: 0.68).delay(0.15),
                    value: appeared
                )

                // ── Text ─────────────────────────────────────────────────
                VStack(spacing: 16) {
                    Text("Monitor Your Network")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 22)
                        .animation(.easeOut(duration: 0.55).delay(0.38), value: appeared)

                    Text("Real-time speed, data usage and network tools\nin a single app")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.66))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 22)
                        .animation(.easeOut(duration: 0.55).delay(0.52), value: appeared)
                }
                .padding(.horizontal, 36)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { iconBounce.toggle() }
        }
    }

    // Animated MeshGradient background (iOS 18+)
    private var meshBackground: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let cx = Float(0.5 + 0.18 * sin(t * 0.45))
            let cy = Float(0.5 + 0.14 * cos(t * 0.60))
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2<Float>(0, 0),    SIMD2<Float>(0.5, 0),    SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, 0.5),  SIMD2<Float>(cx,  cy),   SIMD2<Float>(1, 0.5),
                    SIMD2<Float>(0, 1),    SIMD2<Float>(0.5, 1),    SIMD2<Float>(1, 1)
                ],
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.18),
                    Color(red: 0.06, green: 0.07, blue: 0.28),
                    Color(red: 0.09, green: 0.04, blue: 0.20),
                    Color(red: 0.07, green: 0.05, blue: 0.24),
                    Color(red: 0.14, green: 0.14, blue: 0.52),
                    Color(red: 0.20, green: 0.05, blue: 0.38),
                    Color(red: 0.04, green: 0.04, blue: 0.14),
                    Color(red: 0.09, green: 0.05, blue: 0.30),
                    Color(red: 0.05, green: 0.04, blue: 0.18)
                ]
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Page 2 · Real-Time Speed

struct OnboardingSpeedPage: View {
    @Binding var download: Double
    @Binding var upload: Double
    @State private var appeared = false
    @State private var symbolBounce = false

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.06, blue: 0.13).ignoresSafeArea()
            RadialGradient(
                colors: [.blue.opacity(0.16), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 320
            ).ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                Image(systemName: "speedometer")
                    .font(.system(size: 58))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.bounce, value: symbolBounce)

                HStack(spacing: 28) {
                    speedGauge(
                        value: download,
                        label: "Download",
                        icon: "arrow.down.circle.fill",
                        color: .cyan
                    )
                    speedGauge(
                        value: upload,
                        label: "Upload",
                        icon: "arrow.up.circle.fill",
                        color: Color(red: 1, green: 0.46, blue: 0.10)
                    )
                }

                VStack(spacing: 14) {
                    Text("Real-time Monitoring")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Monitor your download and upload speeds\nevery 0.5 seconds")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                .padding(.horizontal, 36)

                Spacer()
                Spacer()
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 28)
            .animation(.easeOut(duration: 0.55), value: appeared)
        }
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { symbolBounce.toggle() }
        }
    }

    @ViewBuilder
    private func speedGauge(value: Double, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.11))
                    .frame(width: 96, height: 96)

                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color.opacity(0.8))

                    Text(String(format: "%.1f", value))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.easeInOut(duration: 0.34), value: value)

                    Text("Mbps")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

// MARK: - Page 3 · Widget & Live Activity

struct OnboardingWidgetPage: View {
    @State private var appeared = false
    @State private var symbolBounce = false
    @State private var widgetDownload: Double = 87.4
    @State private var widgetUpload: Double = 18.2
    @State private var widgetTimer: Timer?

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.04, blue: 0.17).ignoresSafeArea()
            RadialGradient(
                colors: [.purple.opacity(0.15), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 320
            ).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.bounce, value: symbolBounce)

                phoneMockup
                    .scaleEffect(appeared ? 1.0 : 0.82)
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        .spring(response: 0.60, dampingFraction: 0.72).delay(0.18),
                        value: appeared
                    )

                VStack(spacing: 14) {
                    Text("Always Visible")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("See your speed anytime with\nWidgets and Live Activities")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                .padding(.horizontal, 36)

                Spacer()
                Spacer()
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.50), value: appeared)
        }
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { symbolBounce.toggle() }
            widgetTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.50)) {
                    self.widgetDownload = (Double.random(in: 18...130) * 10).rounded() / 10
                    self.widgetUpload   = (Double.random(in: 3...38)  * 10).rounded() / 10
                }
            }
        }
        .onDisappear { widgetTimer?.invalidate() }
    }

    // ── iPhone mockup ────────────────────────────────────────────────────

    private var phoneMockup: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
                .frame(width: 168, height: 296)
                .overlay(
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(Color.white.opacity(0.11), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: 10)

            VStack(spacing: 10) {
                dynamicIslandView
                    .padding(.top, 16)
                    .padding(.horizontal, 14)

                Spacer()

                widgetCardView
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
            .frame(width: 168, height: 296)
        }
    }

    private var dynamicIslandView: some View {
        ZStack {
            Capsule()
                .fill(Color.black)
                .frame(height: 32)

            HStack {
                Image(systemName: "wifi")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)

                Text(String(format: "%.0f", widgetDownload))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text("Mbps")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.cyan)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var widgetCardView: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.11, blue: 0.26),
                        Color(red: 0.06, green: 0.07, blue: 0.19)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: 95)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
            .overlay(
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.cyan)
                            Text("Download")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Text(String(format: "%.1f", widgetDownload))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                            .contentTransition(.numericText())
                        Text("Mbps")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 1, height: 46)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.orange)
                            Text("Upload")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Text(String(format: "%.1f", widgetUpload))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                            .contentTransition(.numericText())
                        Text("Mbps")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
            )
    }
}

// MARK: - Page 4 · Notification Permission

struct OnboardingNotificationPage: View {
    let onNext: () -> Void
    @State private var appeared = false
    @State private var symbolBounce = false
    @State private var permissionGranted = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.05, blue: 0.03).ignoresSafeArea()
            RadialGradient(
                colors: [.orange.opacity(0.14), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 320
            ).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.bounce, value: symbolBounce)

                VStack(spacing: 14) {
                    Text("Stay Informed")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Get instant notifications when speed drops\nor connection is lost")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                .padding(.horizontal, 36)

                VStack(spacing: 13) {
                    permissionFeatureRow("bolt.fill", .yellow, "Speed alerts")
                    permissionFeatureRow("wifi.exclamationmark", .orange, "Disconnection notifications")
                    permissionFeatureRow("chart.bar.fill", .red, "Daily data summary")
                }
                .padding(.horizontal, 44)

                Spacer()

                // Action buttons (bottom, above global controls overlay)
                VStack(spacing: 14) {
                    Button(action: requestNotification) {
                        HStack(spacing: 8) {
                            Image(systemName: permissionGranted ? "checkmark.circle.fill" : "bell.fill")
                            Text(permissionGranted ? "Granted" : "Allow")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(permissionGranted ? Color.green : Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(permissionGranted)

                    Button("Not Now", action: onNext)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 160)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 28)
            .animation(.easeOut(duration: 0.55), value: appeared)
        }
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { symbolBounce.toggle() }
        }
    }

    private func requestNotification() {
        // Use shared manager so `didRequestNotificationPermission` flag is correctly set
        NotificationManager.shared.requestPermission()
        withAnimation(.spring(response: 0.30)) { permissionGranted = true }
        // User advances manually via the İleri button in the overlay.
    }

    private func permissionFeatureRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 26)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
            Spacer()
        }
    }
}

// MARK: - Page 5 · Location Permission

/// Thin `ObservableObject` wrapper so CLLocationManager persists as a StateObject.
private final class OnboardingLocationRequester: NSObject, ObservableObject,
    CLLocationManagerDelegate
{
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUse() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}

struct OnboardingLocationPage: View {
    let onComplete: () -> Void
    @StateObject private var locationRequester = OnboardingLocationRequester()
    @State private var appeared = false
    @State private var symbolBounce = false
    @State private var permissionRequested = false

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.08, blue: 0.05).ignoresSafeArea()
            RadialGradient(
                colors: [.green.opacity(0.14), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 320
            ).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "location.fill.viewfinder")
                    .font(.system(size: 62))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.bounce, value: symbolBounce)

                VStack(spacing: 14) {
                    Text("For WiFi Details")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("We need location permission to\nview SSID and network details")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                .padding(.horizontal, 36)

                VStack(spacing: 13) {
                    locationFeatureRow("wifi", .green, "WiFi network name (SSID)")
                    locationFeatureRow("info.circle.fill", .teal, "Network security info")
                    locationFeatureRow("lock.shield.fill", .mint, "Connected network details")
                }
                .padding(.horizontal, 44)

                Spacer()

                // Action buttons (bottom, above global controls overlay)
                VStack(spacing: 14) {
                    Button(action: requestLocation) {
                        HStack(spacing: 8) {
                            Image(
                                systemName: permissionRequested
                                    ? "checkmark.circle.fill" : "location.fill"
                            )
                            Text(permissionRequested ? "Requested" : "Allow")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(permissionRequested ? Color(white: 0.45) : Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(permissionRequested)

                    Button("Not Now", action: onComplete)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 160)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 28)
            .animation(.easeOut(duration: 0.55), value: appeared)
        }
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { symbolBounce.toggle() }
        }
    }

    private func requestLocation() {
        withAnimation(.spring(response: 0.30)) { permissionRequested = true }
        locationRequester.requestWhenInUse()
        // User advances manually via the Başlayalım button in the overlay.
    }

    private func locationFeatureRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 26)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
            Spacer()
        }
    }
}
