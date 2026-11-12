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

    /// Rendered as rows inside the Settings "Notifications" `AppSection` card.
    var body: some View {
        VStack(spacing: 0) {
            permissionRow

            AppRowDivider()

            notificationToggleRow(
                icon: "wifi.slash",
                title: "Disconnect",
                subtitle: "Notify when disconnected",
                isOn: $manager.notifyOnDisconnect,
                tint: AppTheme.danger
            )

            AppRowDivider()

            VStack(spacing: 0) {
                notificationToggleRow(
                    icon: "chart.pie.fill",
                    title: "Data Limit",
                    subtitle: "Notify when approaching your cellular data limit",
                    isOn: $manager.notifyOnDataLimit,
                    tint: AppTheme.upload
                )

                if manager.notifyOnDataLimit {
                    sliderRow(
                        title: "Data Limit Threshold",
                        valueText: (manager.dataLimitThresholdPercent / 100).formatted(.percent.precision(.fractionLength(0))),
                        value: $manager.dataLimitThresholdPercent,
                        range: 50...95,
                        step: 1,
                        tint: AppTheme.upload
                    )
                }
            }

            AppRowDivider()

            notificationToggleRow(
                icon: "arrow.down.right.circle.fill",
                title: "Speed Drop",
                subtitle: "Notify when a speed test is far below your usual result",
                isOn: $manager.notifyOnSpeedDrop,
                tint: AppTheme.warning
            )

            AppRowDivider()

            VStack(spacing: 0) {
                notificationToggleRow(
                    icon: "bolt.fill",
                    title: "Speed Peak",
                    subtitle: "Notify on speed peak",
                    isOn: $manager.notifyOnSpeedPeak,
                    tint: AppTheme.ping
                )

                if manager.notifyOnSpeedPeak {
                    sliderRow(
                        title: "Speed Peak Threshold",
                        valueText: manager.speedPeakThreshold.fixed(0) + " MB/s",
                        value: $manager.speedPeakThreshold,
                        range: 10...500,
                        step: 5,
                        tint: AppTheme.ping
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: manager.notifyOnDataLimit)
        .animation(.easeInOut(duration: 0.25), value: manager.notifyOnSpeedPeak)
        .task {
            await manager.refreshAuthorizationStatus()
        }
    }

    private var permissionRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppRow(
                icon: "bell.badge.fill",
                tint: permissionTint,
                title: "Notification Permission",
                subtitle: LocalizedStringKey(permissionDescription)
            ) {
                Toggle("Notification Permission", isOn: permissionBinding)
                    .labelsHidden()
                    .tint(permissionTint)
                    .disabled(manager.authorizationStatus == .authorized || manager.authorizationStatus == .provisional)
            }

            if shouldShowSettingsButton {
                Button {
                    manager.openAppSettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .appFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundStyle(AppTheme.danger)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(AppTheme.danger.opacity(0.16), in: Capsule())
                }
                .buttonStyle(AppPressableButtonStyle())
                .padding(.leading, 70)
                .padding(.bottom, 12)
            }
        }
    }

    private func notificationToggleRow(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isOn: Binding<Bool>,
        tint: Color
    ) -> some View {
        AppRow(icon: icon, tint: tint, title: title, subtitle: subtitle) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(tint)
        }
    }

    /// Threshold slider indented under its toggle row (aligned with the row text).
    private func sliderRow(
        title: LocalizedStringKey,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .appFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text(valueText)
                    .appFont(size: 13, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.ink)
            }

            Slider(value: value, in: range, step: step)
                .tint(tint)
        }
        .padding(.leading, 70)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
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
            return String(localized: "Notifications enabled.")
        case .provisional:
            return String(localized: "Provisional notification permission enabled.")
        case .denied:
            return String(localized: "Notification permission denied.")
        case .notDetermined:
            return String(localized: "Permission not yet granted.")
        case .ephemeral:
            return String(localized: "Ephemeral session permission active.")
        @unknown default:
            return String(localized: "Notification status unknown.")
        }
    }

    private var permissionTint: Color {
        switch manager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return AppTheme.ping
        case .denied:
            return AppTheme.danger
        case .notDetermined:
            return AppTheme.upload
        @unknown default:
            return .gray
        }
    }
}

#Preview {
    ScrollView {
        AppSection("Notifications") {
            NotificationsSettingsView()
        }
        .padding(AppTheme.pagePadding)
    }
    .appPageBackground()
    .preferredColorScheme(.dark)
}
