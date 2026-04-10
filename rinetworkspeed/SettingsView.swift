//
//  SettingsView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: NetworkStatsMonitor

    @AppStorage("updateInterval") private var updateInterval: Double = 0.5
    @AppStorage("speedUnit") private var speedUnit: String = "bytes"
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = true
    @AppStorage("dataLimitEnabled") private var dataLimitEnabled: Bool = false
    @AppStorage("dataLimitGB") private var dataLimitGB: Double = 5.0
    @AppStorage("dataLimitResetDay") private var dataLimitResetDay: Int = 1

    var body: some View {
        NavigationStack {
            List {
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
                                Text("Hiz Birimi")
                                    .foregroundStyle(.white)
                                Text(speedUnit == "bits" ? "Mbps" : "MB/s")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                        }
                        .tint(.blue)
                    }

                    settingsRow(icon: "circle.lefthalf.filled", iconColor: .indigo) {
                        Picker("Tema", selection: $appTheme) {
                            Text("System").tag("system")
                            Text("Dark").tag("dark")
                            Text("Light").tag("light")
                        }
                        .tint(.white)
                    }
                } header: {
                    sectionHeader("Genel")
                }

                Section {
                    settingsRow(icon: "dot.radiowaves.left.and.right", iconColor: .green) {
                        Toggle("Live Activity", isOn: $liveActivityEnabled)
                            .tint(.green)
                            .foregroundStyle(.white)
                    }
                } header: {
                    sectionHeader("Live Activity")
                }

                Section {
                    settingsRow(icon: "externaldrive.fill.badge.wifi", iconColor: .orange) {
                        Toggle("Veri Limiti Uyarisi", isOn: $dataLimitEnabled)
                            .tint(.orange)
                            .foregroundStyle(.white)
                    }

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
                            Picker("Sifirlama Gunu", selection: $dataLimitResetDay) {
                                ForEach(1...28, id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                            .tint(.white)
                        }
                    }

                } header: {
                    sectionHeader("Veri Limiti")
                }
                .animation(.easeInOut(duration: 0.25), value: dataLimitEnabled)

                Section {
                    NotificationsSettingsView()
                } header: {
                    sectionHeader("Bildirimler")
                }

                Section {
                    settingsRow(icon: "app.badge.fill", iconColor: .cyan) {
                        HStack {
                            Text("Uygulama Surumu")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(appVersion)
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }

                    settingsRow(icon: "heart.fill", iconColor: .pink) {
                        HStack {
                            Text("Gelistirici")
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
                                Text("Geri Bildirim Gonder")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            .foregroundStyle(.white)
                        }
                    }
                } header: {
                    sectionHeader("Hakkinda")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255))
            .listStyle(.insetGrouped)
            .navigationTitle("Ayarlar")
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
