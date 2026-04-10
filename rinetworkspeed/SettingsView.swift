//
//  SettingsView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import AppIntents

struct SettingsView: View {
    @ObservedObject var monitor: NetworkStatsMonitor
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    @AppStorage("updateInterval") private var updateInterval: Double = 0.5
    @AppStorage("speedUnit") private var speedUnit: String = "bytes"
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = true
    @AppStorage("dataLimitEnabled") private var dataLimitEnabled: Bool = false
    @AppStorage("dataLimitGB") private var dataLimitGB: Double = 5.0
    @AppStorage("dataLimitResetDay") private var dataLimitResetDay: Int = 1

    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: Pro upgrade banner (free users only)
                if !purchaseManager.isPro {
                    Section {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    LinearGradient(
                                        colors: [Color(red: 0.24, green: 0.45, blue: 0.99),
                                                 Color(red: 0.55, green: 0.28, blue: 0.96)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .frame(width: 36, height: 36)

                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("ri Pro")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("Unlock all features")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.55))
                                }

                                Spacer()

                                Text("Upgrade")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(
                                            LinearGradient(
                                                colors: [Color(red: 0.24, green: 0.45, blue: 0.99),
                                                         Color(red: 0.55, green: 0.28, blue: 0.96)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                    )
                            }
                        }
                        .listRowBackground(Color(red: 0.10, green: 0.10, blue: 0.18))
                        .fullScreenCover(isPresented: $showingPaywall) {
                            PaywallView()
                        }
                    }
                }

                Section {
                    Picker("Update Interval", selection: $updateInterval) {
                        Text("0.5s").tag(0.5)
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color(red: 0.11, green: 0.11, blue: 0.13))

                    settingsRow(icon: "speedometer", iconColor: .blue) {
                        Toggle(isOn: speedUnitBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Speed Unit")
                                    .foregroundStyle(.white)
                                Text(speedUnit == "bits" ? "Mbps" : "MB/s")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                        }
                        .tint(.blue)
                    }

                    settingsRow(icon: "circle.lefthalf.filled", iconColor: .indigo) {
                        Picker("Theme", selection: $appTheme) {
                            Text("System").tag("system")
                            Text("Dark").tag("dark")
                            Text("Light").tag("light")
                        }
                        .tint(.white)
                    }
                } header: {
                    sectionHeader("General")
                }

                Section {
                    settingsRow(icon: "dot.radiowaves.left.and.right", iconColor: .green) {
                        Toggle("Live Activity", isOn: $liveActivityEnabled)
                            .tint(.green)
                            .foregroundStyle(.white)
                    }
                    .proGated(feature: .widget)
                } header: {
                    sectionHeader("Live Activity")
                }

                Section {
                    settingsRow(icon: "externaldrive.fill.badge.wifi", iconColor: .orange) {
                        Toggle("Data Limit Alert", isOn: $dataLimitEnabled)
                            .tint(.orange)
                            .foregroundStyle(.white)
                    }
                    .proGated(feature: .dataLimit)

                    if dataLimitEnabled {
                        settingsRow(icon: "chart.bar.xaxis", iconColor: .orange) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Limit")
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("\(dataLimitGB, specifier: "%.1f") GB")
                                        .foregroundStyle(.white.opacity(0.62))
                                }

                                Slider(value: $dataLimitGB, in: 1...50, step: 0.5)
                                    .tint(.orange)
                            }
                        }

                        settingsRow(icon: "calendar", iconColor: .pink) {
                            Picker("Reset Day", selection: $dataLimitResetDay) {
                                ForEach(1...28, id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                            .tint(.white)
                        }
                    }

                } header: {
                    sectionHeader("Data Limit")
                }
                .animation(.easeInOut(duration: 0.25), value: dataLimitEnabled)

                Section {
                    if purchaseManager.isPro {
                        NotificationsSettingsView()
                    } else {
                        proLockedRow(feature: .notifications)
                    }
                } header: {
                    sectionHeader("Notifications")
                }

                // MARK: Siri & Shortcuts
                Section {
                    // Tip cards — one per intent
                    if #available(iOS 16, *) {
                        SiriTipView(intent: GetNetworkSpeedIntent())
                            .listRowBackground(Color(red: 0.11, green: 0.11, blue: 0.13))

                        SiriTipView(intent: GetDataUsageIntent())
                            .listRowBackground(Color(red: 0.11, green: 0.11, blue: 0.13))

                        SiriTipView(intent: RunSpeedTestIntent())
                            .listRowBackground(Color(red: 0.11, green: 0.11, blue: 0.13))

                        SiriTipView(intent: GetPingIntent())
                            .listRowBackground(Color(red: 0.11, green: 0.11, blue: 0.13))
                    }

                    // Open Shortcuts app
                    if #available(iOS 16.4, *) {
                        settingsRow(icon: "arrow.up.forward.app.fill", iconColor: .orange) {
                            ShortcutsLink()
                                .shortcutsLinkStyle(.automaticOutline)
                                .tint(.orange)
                        }
                    } else {
                        // Fallback: open Shortcuts via URL
                        settingsRow(icon: "arrow.up.forward.app.fill", iconColor: .orange) {
                            Link(destination: URL(string: "shortcuts://")!) {
                                HStack {
                                    Text("Open Shortcuts App")
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                            }
                        }
                    }
                } header: {
                    sectionHeader("Siri & Shortcuts")
                } footer: {
                    Text("You can say commands like \"Show my speed with rinetworkspeed\" to Siri. Automations can be created in the Shortcuts app.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Section {
                    settingsRow(icon: "app.badge.fill", iconColor: .cyan) {
                        HStack {
                            Text("App Version")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(appVersion)
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }

                    settingsRow(icon: "heart.fill", iconColor: .pink) {
                        HStack {
                            Text("Developer")
                                .foregroundStyle(.white)
                            Spacer()
                            Label("Eray", systemImage: "heart.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.white.opacity(0.82), .pink)
                        }
                    }

                    settingsRow(icon: "envelope.fill", iconColor: .teal) {
                        Link(destination: URL(string: "mailto:feedback@rinetworkspeed.app")!) {
                            HStack {
                                Text("Send Feedback")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            .foregroundStyle(.white)
                        }
                    }
                } header: {
                    sectionHeader("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255))
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
        .tint(.white)
        .background(Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255))
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

    @ViewBuilder
    private func proLockedRow(feature: ProFeature) -> some View {
        Button { showingPaywall = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.24, green: 0.45, blue: 0.99))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.24, green: 0.45, blue: 0.99).opacity(0.15))
                    )

                Text(feature.rawValue)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                Text("Pro")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color(red: 0.24, green: 0.45, blue: 0.99),
                                         Color(red: 0.55, green: 0.28, blue: 0.96)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
            }
        }
        .listRowBackground(Color(red: 0.11, green: 0.11, blue: 0.13))
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.42))
    }

    private func settingsRow<Content: View>(
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(iconColor.gradient)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

            content()
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .listRowBackground(Color(red: 0.11, green: 0.11, blue: 0.13))
        .listRowSeparatorTint(.white.opacity(0.08))
    }
}

#Preview {
    SettingsView(monitor: NetworkStatsMonitor())
}
