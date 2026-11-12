//
//  OnboardingView.swift
//  rinetworkspeed
//
//  Three pages: welcome, what the app does, and the notification permission.
//  Location permission is not asked here; it is requested the first time the
//  user opens the Wi-Fi details, where its purpose is obvious.
//

import SwiftUI

// MARK: - Main Onboarding Shell

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var currentPage: Int = 0

    private let totalPages = 3

    private var isLastPage: Bool { currentPage == totalPages - 1 }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            TabView(selection: $currentPage) {
                OnboardingWelcomePage()
                    .tag(0)

                OnboardingFeaturesPage()
                    .tag(1)

                OnboardingNotificationPage(onFinish: completeOnboarding)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // ── Controls overlay ─────────────────────────────────────────
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if !isLastPage {
                        Button("Skip") { completeOnboarding() }
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(AppTheme.cardFill))
                            .overlay(Capsule().stroke(AppTheme.cardStroke, lineWidth: 1))
                    }
                }
                .frame(minHeight: 36)
                .padding(.top, 8)
                .padding(.horizontal, AppTheme.pagePadding)

                Spacer()

                VStack(spacing: 22) {
                    OnboardingPageIndicator(count: totalPages, current: currentPage)

                    // The last page has its own Allow / Not Now actions.
                    if !isLastPage {
                        Button(action: goToNext) {
                            HStack(spacing: 8) {
                                Text("Next")
                                Image(systemName: "arrow.right")
                                    .font(.system(.footnote, weight: .bold))
                            }
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: Actions

    private func goToNext() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
            currentPage = min(currentPage + 1, totalPages - 1)
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}

// MARK: - Shared Building Blocks

/// Capsule page indicator; the active page stretches and takes the accent color.
private struct OnboardingPageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AppTheme.accent : AppTheme.cardStroke)
                    .frame(width: index == current ? 24 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(current + 1) of \(count)"))
    }
}

/// Large solid icon tile used as the hero of every page.
private struct OnboardingHeroIcon: View {
    let systemName: String
    let tint: Color
    var bounce: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .appFont(size: 40, weight: .semibold)
            .foregroundStyle(.white)
            .symbolEffect(.bounce, value: bounce)
            .frame(width: 92, height: 92)
            .background(tint, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: tint.opacity(0.4), radius: 20, x: 0, y: 10)
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
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.system(.body, design: .rounded))
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

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 20)
            .animation(.easeOut(duration: 0.5), value: appeared)
    }
}

private extension View {
    func onboardingAppear(_ appeared: Bool) -> some View {
        modifier(OnboardingAppearModifier(appeared: appeared))
    }
}

/// Scrollable page body so large Dynamic Type sizes never clip content.
private struct OnboardingPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                content
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 72)
            // Leaves room for the page indicator and Next button overlay.
            .padding(.bottom, 150)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Page 1 · Welcome

struct OnboardingWelcomePage: View {
    @State private var appeared = false
    @State private var iconBounce = false

    var body: some View {
        OnboardingPage {
            Spacer(minLength: 40)

            OnboardingHeroIcon(systemName: "wifi", tint: AppTheme.accent, bounce: iconBounce)

            OnboardingTitleBlock(
                title: "Monitor Your Network",
                subtitle: "Speed tests, live speed, data usage and network tools in a single app."
            )
        }
        .onboardingAppear(appeared)
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { iconBounce.toggle() }
        }
    }
}

// MARK: - Page 2 · Features

struct OnboardingFeaturesPage: View {
    @State private var appeared = false

    var body: some View {
        OnboardingPage {
            OnboardingHeroIcon(systemName: "speedometer", tint: AppTheme.download)

            OnboardingTitleBlock(
                title: "Everything at a Glance",
                subtitle: "Know how fast your connection really is and where your data goes."
            )

            AppSection {
                AppRow(
                    icon: "bolt.fill",
                    tint: AppTheme.download,
                    title: "Speed Test",
                    subtitle: "Download, upload and ping in about 20 seconds"
                )
                AppRowDivider()
                AppRow(
                    icon: "waveform.path.ecg",
                    tint: AppTheme.ping,
                    title: "Live Speed",
                    subtitle: "Second by second, also in a Live Activity"
                )
                AppRowDivider()
                AppRow(
                    icon: "chart.pie.fill",
                    tint: AppTheme.upload,
                    title: "Data Usage",
                    subtitle: "Wi-Fi and cellular, with a monthly limit"
                )
                AppRowDivider()
                AppRow(
                    icon: "rectangle.stack.fill",
                    tint: AppTheme.accent,
                    title: "Widgets",
                    subtitle: "Your last test on the Home Screen"
                )
            }
            .padding(.horizontal, AppTheme.pagePadding)
        }
        .onboardingAppear(appeared)
        .onAppear { appeared = true }
    }
}

// MARK: - Page 3 · Notification Permission

struct OnboardingNotificationPage: View {
    let onFinish: () -> Void
    @State private var appeared = false
    @State private var symbolBounce = false

    var body: some View {
        OnboardingPage {
            OnboardingHeroIcon(systemName: "bell.badge.fill", tint: AppTheme.upload, bounce: symbolBounce)

            OnboardingTitleBlock(
                title: "Stay Informed",
                subtitle: "Get notified when your connection drops, a test is unusually slow or you near your data limit."
            )

            AppSection {
                AppRow(icon: "wifi.exclamationmark", tint: AppTheme.upload, title: "Disconnection alerts")
                AppRowDivider()
                AppRow(icon: "arrow.down.right.circle.fill", tint: AppTheme.warning, title: "Speed drop alerts")
                AppRowDivider()
                AppRow(icon: "chart.pie.fill", tint: AppTheme.danger, title: "Data limit warnings")
            }
            .padding(.horizontal, AppTheme.pagePadding)

            VStack(spacing: 10) {
                Button(action: allowNotifications) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                        Text("Allow Notifications")
                    }
                }
                .buttonStyle(AppPrimaryButtonStyle())

                Button("Not Now", action: onFinish)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, AppTheme.pagePadding)
        }
        .onboardingAppear(appeared)
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { symbolBounce.toggle() }
        }
    }

    private func allowNotifications() {
        // The shared manager records that the prompt was shown.
        NotificationManager.shared.requestPermission()
        onFinish()
    }
}

#Preview {
    OnboardingView()
}
