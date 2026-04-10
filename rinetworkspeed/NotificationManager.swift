//
//  NotificationManager.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Combine
import UserNotifications
import UIKit

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @AppStorage("notifyOnSpeedDrop") var notifyOnSpeedDrop: Bool = true
    @AppStorage("speedDropThreshold") var speedDropThreshold: Double = 1.0
    @AppStorage("notifyOnDisconnect") var notifyOnDisconnect: Bool = true
    @AppStorage("notifyOnDataLimit") var notifyOnDataLimit: Bool = true
    @AppStorage("dataLimitThresholdPercent") var dataLimitThresholdPercent: Double = 80.0
    @AppStorage("notifyOnSpeedPeak") var notifyOnSpeedPeak: Bool = false
    @AppStorage("speedPeakThreshold") var speedPeakThreshold: Double = 100.0
    @AppStorage("didRequestNotificationPermission") private var didRequestNotificationPermission: Bool = false

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()
    private let cooldownInterval: TimeInterval = 60
    private var lastNotificationDates: [String: Date] = [:]
    private var lastObservedSpeed: Double?
    private var lastObservedConnectionState: Bool?
    private var hasReachedDataLimitThreshold = false
    private var hasReachedSpeedPeakThreshold = false
    private var hasDroppedBelowSpeedThreshold = false

    private override init() {
        super.init()
        center.delegate = self
        configureNotificationCategories()
        Task {
            await refreshAuthorizationStatus()
        }
    }

    func requestPermission() {
        guard !didRequestNotificationPermission else {
            Task {
                await refreshAuthorizationStatus()
            }
            return
        }

        didRequestNotificationPermission = true

        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                authorizationStatus = granted ? .authorized : .denied
            } catch {
                authorizationStatus = .denied
            }
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func checkSpeedDrop(current: Double) {
        guard notifyOnSpeedDrop else {
            hasDroppedBelowSpeedThreshold = false
            lastObservedSpeed = current
            return
        }

        let thresholdBytes = speedDropThreshold * 1_048_576
        let previousSpeed = lastObservedSpeed
        let isBelowThreshold = current > 0 && current < thresholdBytes
        let wasAboveThreshold = (previousSpeed ?? thresholdBytes) >= thresholdBytes

        if isBelowThreshold && wasAboveThreshold && !hasDroppedBelowSpeedThreshold {
            notifyIfNeeded(
                type: NotificationType.speedDrop.rawValue,
                title: "Speed Drop Detected",
                body: String(format: "Current throughput dropped to %.2f MB/s.", megabytesPerSecond(from: current)),
                category: NotificationCategory.speedDrop.rawValue
            )
        }

        hasDroppedBelowSpeedThreshold = isBelowThreshold
        lastObservedSpeed = current
    }

    func checkDisconnect(isConnected: Bool) {
        defer {
            lastObservedConnectionState = isConnected
        }

        guard notifyOnDisconnect else { return }
        guard let lastObservedConnectionState, lastObservedConnectionState, !isConnected else { return }

        notifyIfNeeded(
            type: NotificationType.disconnect.rawValue,
            title: "Connection Lost",
            body: "Your device is no longer connected to a network.",
            category: NotificationCategory.disconnect.rawValue
        )
    }

    func checkDataLimit(usedGB: Double, limitGB: Double) {
        guard notifyOnDataLimit, limitGB > 0 else {
            hasReachedDataLimitThreshold = false
            return
        }

        let currentPercent = (usedGB / limitGB) * 100
        let hasReachedThreshold = currentPercent >= dataLimitThresholdPercent

        if hasReachedThreshold && !hasReachedDataLimitThreshold {
            notifyIfNeeded(
                type: NotificationType.dataLimit.rawValue,
                title: "Data Limit Warning",
                body: String(format: "You have used %.0f%% of your %.1f GB limit.", currentPercent, limitGB),
                category: NotificationCategory.dataLimit.rawValue
            )
        }

        hasReachedDataLimitThreshold = hasReachedThreshold
    }

    func checkSpeedPeak(current: Double) {
        guard notifyOnSpeedPeak else {
            hasReachedSpeedPeakThreshold = false
            return
        }

        let thresholdBytes = speedPeakThreshold * 1_048_576
        let hasReachedThreshold = current >= thresholdBytes

        if hasReachedThreshold && !hasReachedSpeedPeakThreshold {
            notifyIfNeeded(
                type: NotificationType.speedPeak.rawValue,
                title: "Speed Peak Reached",
                body: String(format: "Throughput climbed above %.0f MB/s.", speedPeakThreshold),
                category: NotificationCategory.speedPeak.rawValue
            )
        }

        hasReachedSpeedPeakThreshold = hasReachedThreshold
    }

    private func configureNotificationCategories() {
        let openAppAction = UNNotificationAction(
            identifier: NotificationAction.openApp.rawValue,
            title: "Open App",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: NotificationAction.dismiss.rawValue,
            title: "Dismiss",
            options: []
        )
        let reviewUsageAction = UNNotificationAction(
            identifier: NotificationAction.reviewUsage.rawValue,
            title: "Review Usage",
            options: [.foreground]
        )
        let retryAction = UNNotificationAction(
            identifier: NotificationAction.retry.rawValue,
            title: "Retry",
            options: [.foreground]
        )

        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(
                identifier: NotificationCategory.speedDrop.rawValue,
                actions: [openAppAction, dismissAction],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategory.disconnect.rawValue,
                actions: [retryAction, dismissAction],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategory.dataLimit.rawValue,
                actions: [reviewUsageAction, dismissAction],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategory.speedPeak.rawValue,
                actions: [openAppAction, dismissAction],
                intentIdentifiers: []
            )
        ]

        center.setNotificationCategories(categories)
    }

    private func notifyIfNeeded(type: String, title: String, body: String, category: String) {
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        guard canSendNotification(for: type) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category

        let request = UNNotificationRequest(
            identifier: "\(type)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request)
        lastNotificationDates[type] = Date()
    }

    private func canSendNotification(for type: String) -> Bool {
        guard let lastDate = lastNotificationDates[type] else { return true }
        return Date().timeIntervalSince(lastDate) >= cooldownInterval
    }

    private func megabytesPerSecond(from bytesPerSecond: Double) -> Double {
        bytesPerSecond / 1_048_576
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

private enum NotificationType: String {
    case speedDrop
    case disconnect
    case dataLimit
    case speedPeak
}

private enum NotificationCategory: String {
    case speedDrop = "network.speed.drop"
    case disconnect = "network.disconnect"
    case dataLimit = "network.data.limit"
    case speedPeak = "network.speed.peak"
}

private enum NotificationAction: String {
    case openApp = "network.action.open"
    case dismiss = "network.action.dismiss"
    case reviewUsage = "network.action.reviewUsage"
    case retry = "network.action.retry"
}
