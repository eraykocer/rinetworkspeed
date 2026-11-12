//
//  SettingsView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import AppIntents

struct SettingsView: View {
    /// Only methods are called on the monitor; observing it re-rendered the list every tick.
    let monitor: NetworkStatsMonitor
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    @AppStorage("updateInterval") private var updateInterval: Double = 1.0
    @AppStorage("speedUnit") private var speedUnit: String = "bytes"
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = true
    @AppStorage("dataLimitEnabled") private var dataLimitEnabled: Bool = false
    @AppStorage("dataLimitGB") private var dataLimitGB: Double = 5.0
    @AppStorage("dataLimitResetDay") private var dataLimitResetDay: Int = 1

    @State private var showingPaywall = false

    private static let shortcutsURL = URL(string: "shortcuts://")
    private static let feedbackURL = URL(string: "mailto:feedback@rinetworkspeed.app")

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    proHeroCard
                    generalSection
                    liveActivitySection
                    dataLimitSection
                    notificationsSection
                    siriSection
                    aboutSection
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .appPageBackground()
            .navigationTitle("Settings")
            .fullScreenCover(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
        .tint(.white)
        .appPageBackground()
        .onAppear {
            monitor.applyUpdateInterval()
            monitor.applyLiveActivitySetting()
        }
        .onChange(of: updateInterval) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                monitor.applyUpdateInterval()
            }
        }
        .onChange(of: liveActivityEnabled) { _, isEnabled in
            withAnimation(.easeInOut(duration: 0.2)) {
                if isEnabled {
                    monitor.applyLiveActivitySetting()
                } else {
                    monitor.stopLiveActivity()
                }
            }
        }
    }

    // MARK: - Pro Hero

    @ViewBuilder
    private var proHeroCard: some View {
        if purchaseManager.isPro {
            HStack(spacing: 14) {
                heroIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text("ri Pro")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("All Pro features unlocked")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .appHeroCard()
        } else {
            // Upgrade banner (free users only)
            Button {
                showingPaywall = true
            } label: {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ri Pro")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Unlock all features")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 12)
                        heroIcon
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                        Text("Upgrade")
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
                }
                .appHeroCard()
            }
            .buttonStyle(AppPressableButtonStyle())
        }
    }

    private var heroIcon: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - General

    private var generalSection: some View {
        AppSection("General") {
            VStack(spacing: 0) {
                AppRow(icon: "timer", tint: AppTheme.accent, title: "Update Interval")

                Picker("Update Interval", selection: $updateInterval) {
                    Text("0.5s").tag(0.5)
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            AppRowDivider()

            AppRow(
                icon: "speedometer",
                tint: AppTheme.download,
                title: "Speed Unit",
                subtitle: LocalizedStringKey(speedUnit == "bits" ? "Mbps" : "MB/s")
            ) {
                Toggle("Speed Unit", isOn: speedUnitBinding)
                    .labelsHidden()
                    .tint(AppTheme.download)
            }
        }
    }

    // MARK: - Live Activity

    private var liveActivitySection: some View {
        AppSection("Live Activity") {
            AppRow(icon: "dot.radiowaves.left.and.right", tint: AppTheme.ping, title: "Live Activity") {
                Toggle("Live Activity", isOn: $liveActivityEnabled)
                    .labelsHidden()
                    .tint(AppTheme.ping)
            }
            .proGated(feature: .widget)
        }
    }

    // MARK: - Data Limit

    private var dataLimitSection: some View {
        AppSection("Data Limit") {
            AppRow(icon: "externaldrive.fill.badge.wifi", tint: AppTheme.upload, title: "Data Limit Alert") {
                Toggle("Data Limit Alert", isOn: $dataLimitEnabled)
                    .labelsHidden()
                    .tint(AppTheme.upload)
            }
            .proGated(feature: .dataLimit)

            if dataLimitEnabled {
                AppRowDivider()

                VStack(spacing: 0) {
                    AppRow(icon: "chart.bar.xaxis", tint: AppTheme.upload, title: "Limit") {
                        Text("\(dataLimitGB, specifier: "%.1f") GB")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Slider(value: $dataLimitGB, in: 1...50, step: 0.5)
                        .tint(AppTheme.upload)
                        .padding(.leading, 70)
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                }

                AppRowDivider()

                AppRow(icon: "calendar", tint: .pink, title: "Reset Day") {
                    Picker("Reset Day", selection: $dataLimitResetDay) {
                        ForEach(1...28, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(.white)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: dataLimitEnabled)
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        AppSection("Notifications") {
            if purchaseManager.isPro {
                NotificationsSettingsView()
            } else {
                proLockedRow(feature: .notifications)
            }
        }
    }

    // MARK: - Siri & Shortcuts

    private var siriSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("Siri & Shortcuts")

            // Tip cards — one per intent
            if #available(iOS 16, *) {
                VStack(spacing: 10) {
                    SiriTipView(intent: GetNetworkSpeedIntent())
                    SiriTipView(intent: GetDataUsageIntent())
                    SiriTipView(intent: RunSpeedTestIntent())
                    SiriTipView(intent: GetPingIntent())
                }
            }

            // Open Shortcuts app
            VStack(spacing: 0) {
                if #available(iOS 16.4, *) {
                    HStack(spacing: 14) {
                        AppIconTile(systemName: "arrow.up.forward.app.fill", tint: AppTheme.upload)
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automaticOutline)
                            .tint(AppTheme.upload)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else if let url = Self.shortcutsURL {
                    // Fallback: open Shortcuts via URL
                    Link(destination: url) {
                        AppRow(icon: "arrow.up.forward.app.fill", tint: AppTheme.upload, title: "Open Shortcuts App") {
                            externalLinkIcon
                        }
                    }
                    .buttonStyle(AppRowButtonStyle())
                }
            }
            .appCard(padding: nil)

            Text("You can say commands like \"Show my speed with rinetworkspeed\" to Siri. Automations can be created in the Shortcuts app.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.tertiaryText)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        AppSection("About") {
            AppRow(icon: "app.badge.fill", tint: .cyan, title: "App Version") {
                Text(appVersion)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            AppRowDivider()

            AppRow(icon: "heart.fill", tint: .pink, title: "Developer") {
                Label("Eray", systemImage: "heart.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82), .pink)
            }

            if let url = Self.feedbackURL {
                AppRowDivider()

                Link(destination: url) {
                    AppRow(icon: "envelope.fill", tint: .teal, title: "Send Feedback") {
                        externalLinkIcon
                    }
                }
                .buttonStyle(AppRowButtonStyle())
            }
        }
    }

    // MARK: - Helpers

    private var externalLinkIcon: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.3))
    }

    private func proLockedRow(feature: ProFeature) -> some View {
        Button { showingPaywall = true } label: {
            AppRow(
                icon: feature.systemImage,
                tint: AppTheme.accent,
                title: LocalizedStringKey(feature.rawValue),
                subtitle: "Unlock all features"
            ) {
                HStack(spacing: 8) {
                    AppPill(text: "Pro")
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .buttonStyle(AppRowButtonStyle())
    }

    private var speedUnitBinding: Binding<Bool> {
        Binding(
            get: { speedUnit == "bits" },
            set: { speedUnit = $0 ? "bits" : "bytes" }
        )
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }
}

#Preview {
    SettingsView(monitor: NetworkStatsMonitor())
        .preferredColorScheme(.dark)
}
