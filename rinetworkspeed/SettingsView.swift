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
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage(InternetPlan.Key.provider) private var planProvider: String = ""
    @AppStorage(InternetPlan.Key.download) private var planDownloadMbps: Double = 0
    @AppStorage(InternetPlan.Key.upload) private var planUploadMbps: Double = 0

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
                    internetPlanSection
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
        .tint(AppTheme.ink)
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
                        .appFont(size: 22, weight: .bold, design: .rounded)
                        .foregroundStyle(AppTheme.ink)
                    Text("All Pro features unlocked")
                        .appFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark.seal.fill")
                    .appFont(size: 24, weight: .semibold)
                    .foregroundStyle(AppTheme.ping)
            }
            .appCard(padding: 20)
        } else {
            // Upgrade banner (free users only)
            Button {
                showingPaywall = true
            } label: {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ri Pro")
                                .appFont(size: 24, weight: .bold, design: .rounded)
                                .foregroundStyle(AppTheme.ink)
                            Text("Unlock all features")
                                .appFont(size: 13, weight: .medium, design: .rounded)
                                .foregroundStyle(AppTheme.secondaryText)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 12)
                        heroIcon
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                        Text("Upgrade")
                    }
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(proTint, in: Capsule())
                }
                .appCard(padding: 20)
            }
            .buttonStyle(AppPressableButtonStyle())
        }
    }

    /// Solid accent for the Pro card; lighter than AppTheme.accent for contrast on the dark card.
    private let proTint = Color(red: 0.55, green: 0.42, blue: 0.98)

    private var heroIcon: some View {
        Image(systemName: "crown.fill")
            .appFont(size: 26, weight: .semibold)
            .foregroundStyle(proTint)
            .frame(width: 56, height: 56)
            .background(proTint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - General

    private var generalSection: some View {
        AppSection("General") {
            VStack(spacing: 0) {
                AppRow(icon: "circle.lefthalf.filled", tint: .indigo, title: "Appearance")

                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            AppRowDivider()

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
            .proGated(feature: .widgets)
        }
    }

    // MARK: - Data Limit

    private var dataLimitSection: some View {
        AppSection("Data Limit") {
            AppRow(icon: "externaldrive.fill.badge.wifi", tint: AppTheme.upload, title: "Cellular Data Limit") {
                Toggle("Cellular Data Limit", isOn: $dataLimitEnabled)
                    .labelsHidden()
                    .tint(AppTheme.upload)
            }
            .proGated(feature: .dataLimit)

            if dataLimitEnabled {
                AppRowDivider()

                VStack(spacing: 0) {
                    AppRow(icon: "chart.bar.xaxis", tint: AppTheme.upload, title: "Limit") {
                        Text("\(dataLimitGB, specifier: "%.1f") GB")
                            .appFont(size: 15, weight: .semibold, design: .rounded)
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
                    .tint(AppTheme.ink)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: dataLimitEnabled)
    }

    // MARK: - Internet Plan

    private var internetPlanSection: some View {
        AppSection("Internet Plan", footer: "Used to compare your speed tests with what your provider advertises, and for the ISP report in Test History.") {
            AppRow(icon: "building.2.fill", tint: .teal, title: "Provider") {
                TextField("Optional", text: $planProvider)
                    .multilineTextAlignment(.trailing)
                    .appFont(size: 15, weight: .medium, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                    .textInputAutocapitalization(.words)
                    .frame(maxWidth: 160)
            }
            AppRowDivider()
            planSpeedRow(icon: "arrow.down", tint: AppTheme.download, title: "Advertised Download", value: $planDownloadMbps)
            AppRowDivider()
            planSpeedRow(icon: "arrow.up", tint: AppTheme.upload, title: "Advertised Upload", value: $planUploadMbps)
        }
    }

    private func planSpeedRow(icon: String, tint: Color, title: LocalizedStringKey, value: Binding<Double>) -> some View {
        AppRow(icon: icon, tint: tint, title: title) {
            HStack(spacing: 4) {
                TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 80)
                Text(verbatim: "Mbps")
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .appFont(size: 15, weight: .medium, design: .rounded)
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        AppSection("Notifications") {
            NotificationsSettingsView()
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

            Text("You can say commands like \"Show my speed with RiNetwork\" to Siri. Automations can be created in the Shortcuts app.")
                .appFont(size: 12, weight: .regular, design: .rounded)
                .foregroundStyle(AppTheme.tertiaryText)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        AppSection("About") {
            AppRow(icon: "app.badge.fill", tint: .cyan, title: "App Version") {
                Text(appVersion)
                    .appFont(size: 15, weight: .medium, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            AppRowDivider()

            AppRow(icon: "heart.fill", tint: .pink, title: "Developer") {
                Label("Eray", systemImage: "heart.fill")
                    .labelStyle(.titleAndIcon)
                    .appFont(size: 15, weight: .medium, design: .rounded)
                    .foregroundStyle(AppTheme.ink.opacity(0.82), .pink)
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
            .appFont(size: 13, weight: .semibold)
            .foregroundStyle(AppTheme.ink.opacity(0.3))
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
