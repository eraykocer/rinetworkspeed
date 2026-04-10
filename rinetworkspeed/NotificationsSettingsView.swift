//
//  NotificationsSettingsView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @StateObject private var manager = NotificationManager.shared

    var body: some View {
        Group {
            permissionRow
                .notificationSettingsRowStyle()
            notificationToggleRow(
                title: "Speed Drop",
                subtitle: "Notify when speed drops below threshold",
                isOn: $manager.notifyOnSpeedDrop,
                tint: .blue
            )
            .notificationSettingsRowStyle()

            if manager.notifyOnSpeedDrop {
                sliderRow(
                    title: "Speed Drop Threshold",
                    valueText: String(format: "%.1f MB/s", manager.speedDropThreshold),
                    value: $manager.speedDropThreshold,
                    range: 0.5...10.0,
                    step: 0.5,
                    tint: .blue
                )
                .notificationSettingsRowStyle()
            }

            notificationToggleRow(
                title: "Disconnect",
                subtitle: "Notify when disconnected",
                isOn: $manager.notifyOnDisconnect,
                tint: .red
            )
            .notificationSettingsRowStyle()

            notificationToggleRow(
                title: "Data Limit",
                subtitle: "Notify when approaching data limit",
                isOn: $manager.notifyOnDataLimit,
                tint: .orange
            )
            .notificationSettingsRowStyle()

            if manager.notifyOnDataLimit {
                sliderRow(
                    title: "Data Limit Threshold",
                    valueText: String(format: "%.0f%%", manager.dataLimitThresholdPercent),
                    value: $manager.dataLimitThresholdPercent,
                    range: 50...95,
                    step: 1,
                    tint: .orange
                )
                .notificationSettingsRowStyle()
            }

            notificationToggleRow(
                title: "Speed Peak",
                subtitle: "Notify on speed peak",
                isOn: $manager.notifyOnSpeedPeak,
                tint: .green
            )
            .notificationSettingsRowStyle()

            if manager.notifyOnSpeedPeak {
                sliderRow(
                    title: "Speed Peak Threshold",
                    valueText: String(format: "%.0f MB/s", manager.speedPeakThreshold),
                    value: $manager.speedPeakThreshold,
                    range: 10...500,
                    step: 5,
                    tint: .green
                )
                .notificationSettingsRowStyle()
            }
        }
        .task {
            await manager.refreshAuthorizationStatus()
        }
    }

    private var permissionRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Notification Permission", isOn: permissionBinding)
                    .tint(permissionTint)
                    .disabled(manager.authorizationStatus == .authorized || manager.authorizationStatus == .provisional)
                    .foregroundStyle(.white)

                Text(permissionDescription)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }

            if shouldShowSettingsButton {
                Button("Open Settings") {
                    manager.openAppSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    private func notificationToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: isOn)
                .tint(tint)
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .foregroundStyle(.white)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.white.opacity(0.58))
            }

            Slider(value: value, in: range, step: step)
                .tint(tint)
        }
    }

    private var permissionBinding: Binding<Bool> {
        Binding(
            get: {
                manager.authorizationStatus == .authorized || manager.authorizationStatus == .provisional
            },
            set: { isEnabled in
                if isEnabled {
                    manager.requestPermission()
                } else {
                    manager.openAppSettings()
                }
            }
        )
    }

    private var shouldShowSettingsButton: Bool {
        manager.authorizationStatus == .denied
    }

    private var permissionDescription: String {
        switch manager.authorizationStatus {
        case .authorized:
            return "Notifications enabled."
        case .provisional:
            return "Provisional notification permission enabled."
        case .denied:
            return "Notification permission denied."
        case .notDetermined:
            return "Permission not yet granted."
        case .ephemeral:
            return "Ephemeral session permission active."
        @unknown default:
            return "Notification status unknown."
        }
    }

    private var permissionTint: Color {
        switch manager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }
}

#Preview {
    List {
        Section("Notifications") {
            NotificationsSettingsView()
        }
    }
    .scrollContentBackground(.hidden)
    .background(Color.black)
}

private extension View {
    func notificationSettingsRowStyle() -> some View {
        listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            .listRowBackground(Color(red: 0.11, green: 0.11, blue: 0.13))
            .listRowSeparatorTint(.white.opacity(0.08))
    }
}
