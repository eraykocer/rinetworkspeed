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

    private var isLastPage: Bool { currentPage == totalPages - 1 }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

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
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(AppTheme.cardFill))
                        .overlay(Capsule().stroke(AppTheme.cardStroke, lineWidth: 1))
                        .opacity(isLastPage ? 0 : 1)
                        .disabled(isLastPage)
                }
                .padding(.top, 8)
                .padding(.horizontal, AppTheme.pagePadding)

                Spacer()

                VStack(spacing: 22) {
                    OnboardingPageIndicator(count: totalPages, current: currentPage)

                    Button(action: handleNext) {
                        HStack(spacing: 8) {
                            Text(isLastPage ? "Let's Start" : "Next")
                            Image(systemName: isLastPage ? "checkmark" : "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 14, x: 0, y: 6)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 16)
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

// MARK: - Shared Building Blocks

/// Capsule page indicator; the active page stretches and takes the hero gradient.
private struct OnboardingPageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(
                        index == current
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: AppTheme.heroGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(Color.white.opacity(0.18))
                    )
                    .frame(width: index == current ? 24 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text("\(current + 1) / \(count)"))
    }
}

/// Near-black page background with a soft tinted glow near the hero icon.
private struct OnboardingBackground: View {
    let colors: [Color]

    var body: some View {
        ZStack {
            AppTheme.background

            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 320, height: 320)
                .blur(radius: 110)
                .opacity(0.32)
                .offset(y: -170)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Large gradient icon tile used as the hero of every page.
private struct OnboardingHeroIcon: View {
    let systemName: String
    let colors: [Color]
    var bounce: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(.white)
            .symbolEffect(.bounce, value: bounce)
            .frame(width: 92, height: 92)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: (colors.first ?? AppTheme.accent).opacity(0.45), radius: 22, x: 0, y: 10)
            .accessibilityHidden(true)
    }
}

/// Title + subtitle block shared by all pages.
private struct OnboardingTitleBlock: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.horizontal, 32)
    }
}

/// Entrance transition; falls back to a plain fade when Reduce Motion is on.
private struct OnboardingAppearModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let appeared: Bool
    var delay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 20)
            .animation(.easeOut(duration: 0.5).delay(delay), value: appeared)
    }
}

private extension View {
    func onboardingAppear(_ appeared: Bool, delay: Double = 0) -> some View {
        modifier(OnboardingAppearModifier(appeared: appeared, delay: delay))
    }
}

/// Permission action pair: primary "Allow" and a quiet "Not Now".
private struct OnboardingPermissionActions: View {
    let isDone: Bool
    let doneTitle: LocalizedStringKey
    let icon: String
    let colors: [Color]
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onAllow) {
                HStack(spacing: 8) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : icon)
                    Text(isDone ? doneTitle : "Allow")
                }
            }
            .buttonStyle(AppPrimaryButtonStyle(colors: isDone ? [AppTheme.ping, AppTheme.ping.opacity(0.75)] : colors))
            .disabled(isDone)

            Button("Not Now", action: onSkip)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.vertical, 6)
        }
        .padding(.horizontal, AppTheme.pagePadding + 12)
    }
}

// MARK: - Page 1 · Welcome

struct OnboardingWelcomePage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var iconBounce = false

    var body: some View {
        ZStack {
            OnboardingBackground(colors: AppTheme.heroGradient)

            VStack(spacing: 36) {
                Spacer()

                // ── Hero icon with a soft halo ───────────────────────────
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: AppTheme.heroGradient.map { $0.opacity(0.35) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .frame(width: 150, height: 150)

                    Circle()
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                        .frame(width: 200, height: 200)

                    OnboardingHeroIcon(systemName: "wifi", colors: AppTheme.heroGradient, bounce: iconBounce)
                }
                .scaleEffect(appeared || reduceMotion ? 1.0 : 0.85)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.65, dampingFraction: 0.75).delay(0.1), value: appeared)

                OnboardingTitleBlock(
                    title: "Monitor Your Network",
                    subtitle: "Real-time speed, data usage and network tools\nin a single app"
                )
                .onboardingAppear(appeared, delay: 0.3)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { iconBounce.toggle() }
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
            OnboardingBackground(colors: [AppTheme.download, .cyan])

            VStack(spacing: 36) {
                Spacer()

                OnboardingHeroIcon(
                    systemName: "speedometer",
                    colors: [AppTheme.download, AppTheme.download.opacity(0.6)],
                    bounce: symbolBounce
                )

                HStack(spacing: 12) {
                    speedCard(
                        value: download,
                        label: "Download",
                        icon: "arrow.down",
                        color: AppTheme.download
                    )
                    speedCard(
                        value: upload,
                        label: "Upload",
                        icon: "arrow.up",
                        color: AppTheme.upload
                    )
                }
                .padding(.horizontal, AppTheme.pagePadding + 12)

                OnboardingTitleBlock(
                    title: "Real-time Monitoring",
                    subtitle: "Monitor your download and upload speeds\nevery 0.5 seconds"
                )

                Spacer()
                Spacer()
            }
            .onboardingAppear(appeared)
        }
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { symbolBounce.toggle() }
        }
    }

    private func speedCard(value: Double, label: LocalizedStringKey, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                AppIconTile(systemName: icon, tint: color, size: 24)
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .textCase(.uppercase)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.primaryText)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.easeInOut(duration: 0.34), value: value)

                Text("Mbps")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .appCard()
    }
}

// MARK: - Page 3 · Widget & Live Activity

struct OnboardingWidgetPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var symbolBounce = false
    @State private var widgetDownload: Double = 87.4
    @State private var widgetUpload: Double = 18.2
    @State private var widgetTimer: Timer?

    var body: some View {
        ZStack {
            OnboardingBackground(colors: [AppTheme.accent, .purple])

            VStack(spacing: 28) {
                Spacer()

                OnboardingHeroIcon(
                    systemName: "rectangle.stack.fill",
                    colors: [AppTheme.accent, AppTheme.accent.opacity(0.6)],
                    bounce: symbolBounce
                )

                phoneMockup
                    .scaleEffect(appeared || reduceMotion ? 1.0 : 0.88)
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        .spring(response: 0.60, dampingFraction: 0.78).delay(0.15),
                        value: appeared
                    )

                OnboardingTitleBlock(
                    title: "Always Visible",
                    subtitle: "See your speed anytime with\nWidgets and Live Activities"
                )

                Spacer()
                Spacer()
            }
            .onboardingAppear(appeared)
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
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .frame(width: 164, height: 264)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)

            VStack(spacing: 10) {
                dynamicIslandView
                    .padding(.top, 14)
                    .padding(.horizontal, 14)

                Spacer()

                widgetCardView
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
            }
            .frame(width: 164, height: 264)
        }
        .accessibilityHidden(true)
    }

    private var dynamicIslandView: some View {
        ZStack {
            Capsule()
                .fill(Color.black)
                .frame(height: 30)

            HStack(spacing: 4) {
                Image(systemName: "wifi")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.ping)

                Text(String(format: "%.0f", widgetDownload))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text("Mbps")
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(AppTheme.download)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(AppTheme.upload)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var widgetCardView: some View {
        HStack(spacing: 12) {
            widgetMetric(
                label: "Download",
                icon: "arrow.down",
                value: widgetDownload,
                color: AppTheme.download
            )

            Rectangle()
                .fill(AppTheme.separator)
                .frame(width: 1, height: 42)

            widgetMetric(
                label: "Upload",
                icon: "arrow.up",
                value: widgetUpload,
                color: AppTheme.upload
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 88)
        .background(
            LinearGradient(
                colors: AppTheme.heroGradient.map { $0.opacity(0.35) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        )
    }

    private func widgetMetric(label: LocalizedStringKey, icon: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(String(format: "%.1f", value))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text("Mbps")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

// MARK: - Page 4 · Notification Permission

struct OnboardingNotificationPage: View {
    let onNext: () -> Void
    @State private var appeared = false
    @State private var symbolBounce = false
    @State private var permissionGranted = false

    private let colors = [AppTheme.upload, AppTheme.warning]

    var body: some View {
        ZStack {
            OnboardingBackground(colors: colors)

            VStack(spacing: 28) {
                Spacer()

                OnboardingHeroIcon(systemName: "bell.badge.fill", colors: colors, bounce: symbolBounce)

                OnboardingTitleBlock(
                    title: "Stay Informed",
                    subtitle: "Get instant notifications when speed drops\nor connection is lost"
                )

                AppSection {
                    AppRow(icon: "bolt.fill", tint: AppTheme.warning, title: "Speed alerts")
                    AppRowDivider()
                    AppRow(icon: "wifi.exclamationmark", tint: AppTheme.upload, title: "Disconnection notifications")
                    AppRowDivider()
                    AppRow(icon: "chart.bar.fill", tint: AppTheme.danger, title: "Daily data summary")
                }
                .padding(.horizontal, AppTheme.pagePadding + 12)

                Spacer()

                // Action buttons (bottom, above global controls overlay)
                OnboardingPermissionActions(
                    isDone: permissionGranted,
                    doneTitle: "Granted",
                    icon: "bell.fill",
                    colors: colors,
                    onAllow: requestNotification,
                    onSkip: onNext
                )
                .padding(.bottom, 170)
            }
            .onboardingAppear(appeared)
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

    private let colors = [AppTheme.ping, Color.teal]

    var body: some View {
        ZStack {
            OnboardingBackground(colors: colors)

            VStack(spacing: 28) {
                Spacer()

                OnboardingHeroIcon(systemName: "location.fill.viewfinder", colors: colors, bounce: symbolBounce)

                OnboardingTitleBlock(
                    title: "For WiFi Details",
                    subtitle: "We need location permission to\nview SSID and network details"
                )

                AppSection {
                    AppRow(icon: "wifi", tint: AppTheme.ping, title: "WiFi network name (SSID)")
                    AppRowDivider()
                    AppRow(icon: "info.circle.fill", tint: .teal, title: "Network security info")
                    AppRowDivider()
                    AppRow(icon: "lock.shield.fill", tint: .mint, title: "Connected network details")
                }
                .padding(.horizontal, AppTheme.pagePadding + 12)

                Spacer()

                // Action buttons (bottom, above global controls overlay)
                OnboardingPermissionActions(
                    isDone: permissionRequested,
                    doneTitle: "Requested",
                    icon: "location.fill",
                    colors: colors,
                    onAllow: requestLocation,
                    onSkip: onComplete
                )
                .padding(.bottom, 170)
            }
            .onboardingAppear(appeared)
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
}

#Preview {
    OnboardingView()
}
