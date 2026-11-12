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

    @AppStorage("notifyOnDisconnect") var notifyOnDisconnect: Bool = true
    @AppStorage("notifyOnDataLimit") var notifyOnDataLimit: Bool = true
    @AppStorage("dataLimitThresholdPercent") var dataLimitThresholdPercent: Double = 80.0
    @AppStorage("notifyOnSpeedPeak") var notifyOnSpeedPeak: Bool = false
    @AppStorage("speedPeakThreshold") var speedPeakThreshold: Double = 100.0
    @AppStorage("notifyOnSpeedDrop") var notifyOnSpeedDrop: Bool = true
    /// Billing period (its start date) for which the data limit warning was
    /// already sent, so it fires once per period instead of once per launch.
    @AppStorage("dataLimitNotifiedPeriod") private var dataLimitNotifiedPeriod: String = ""
    @AppStorage("didRequestNotificationPermission") private var didRequestNotificationPermission: Bool = false

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()
    private let cooldownInterval: TimeInterval = 60
    /// A test is a "drop" when its download is below this share of the median.
    private let speedDropRatio = 0.5
    private let speedDropBaselineCount = 5
    private var lastNotificationDates: [String: Date] = [:]
    private var lastObservedConnectionState: Bool?
    private var hasReachedSpeedPeakThreshold = false

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

    func checkDisconnect(isConnected: Bool) {
        defer {
            lastObservedConnectionState = isConnected
        }

        guard notifyOnDisconnect else { return }
        guard let lastObservedConnectionState, lastObservedConnectionState, !isConnected else { return }

        notifyIfNeeded(
            type: NotificationType.disconnect.rawValue,
            title: String(localized: "Connection Lost"),
            body: String(localized: "Your device is no longer connected to a network."),
            category: NotificationCategory.disconnect.rawValue
        )
    }

    /// - Parameters:
    ///   - usedGB: Cellular usage in the current billing period.
    ///   - periodID: Stable identifier of the billing period (its start date).
    func checkDataLimit(usedGB: Double, limitGB: Double, periodID: String) {
        guard notifyOnDataLimit, limitGB > 0 else { return }

        let currentPercent = (usedGB / limitGB) * 100
        guard currentPercent >= dataLimitThresholdPercent else {
            // Usage fell below the threshold again (e.g. the limit was raised),
            // so allow a new warning if it is crossed later in this period.
            if dataLimitNotifiedPeriod == periodID { dataLimitNotifiedPeriod = "" }
            return
        }
        guard dataLimitNotifiedPeriod != periodID else { return }

        dataLimitNotifiedPeriod = periodID
        notifyIfNeeded(
            type: NotificationType.dataLimit.rawValue,
            title: String(localized: "Data Limit Warning"),
            body: String(
                localized: "You have used \(Int(currentPercent.rounded()))% of your \(Self.oneDecimal(limitGB)) GB cellular limit for this billing period."
            ),
            category: NotificationCategory.dataLimit.rawValue
        )
    }

    /// Alerts when a finished speed test is far below the user's recent results.
    /// - Parameters:
    ///   - latestDownload: Download speed of the test that just finished, in bytes/second.
    ///   - previousDownloads: Earlier results, newest first, in bytes/second.
    func checkSpeedDrop(latestDownload: Double, previousDownloads: [Double]) {
        guard notifyOnSpeedDrop else { return }

        let baseline = previousDownloads.filter { $0 > 0 }.prefix(speedDropBaselineCount).sorted()
        // A handful of earlier tests is needed before "typical" means anything.
        guard baseline.count >= 3 else { return }

        let typical = baseline[baseline.count / 2]
        guard typical > 0, latestDownload < typical * speedDropRatio else { return }

        let latestMbps = latestDownload * 8 / 1_000_000
        let typicalMbps = typical * 8 / 1_000_000
        let dropPercent = (1 - latestDownload / typical) * 100

        notifyIfNeeded(
            type: NotificationType.speedDrop.rawValue,
            title: String(localized: "Speed Drop Detected"),
            body: String(
                localized: "Download was \(Self.oneDecimal(latestMbps)) Mbps, \(Int(dropPercent.rounded()))% below your typical \(Self.oneDecimal(typicalMbps)) Mbps."
            ),
            category: NotificationCategory.speedDrop.rawValue
        )
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
                title: String(localized: "Speed Peak Reached"),
                body: String(localized: "Throughput climbed above \(Int(speedPeakThreshold)) MB/s."),
                category: NotificationCategory.speedPeak.rawValue
            )
        }

        hasReachedSpeedPeakThreshold = hasReachedThreshold
    }

    private func configureNotificationCategories() {
        let openAppAction = UNNotificationAction(
            identifier: NotificationAction.openApp.rawValue,
            title: String(localized: "Open App"),
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: NotificationAction.dismiss.rawValue,
            title: String(localized: "Dismiss"),
            options: []
        )
        let reviewUsageAction = UNNotificationAction(
            identifier: NotificationAction.reviewUsage.rawValue,
            title: String(localized: "Review Usage"),
            options: [.foreground]
        )
        let retryAction = UNNotificationAction(
            identifier: NotificationAction.retry.rawValue,
            title: String(localized: "Retry"),
            options: [.foreground]
        )
        let testAgainAction = UNNotificationAction(
            identifier: NotificationAction.testAgain.rawValue,
            title: String(localized: "Test Again"),
            options: [.foreground]
        )

        let categories: Set<UNNotificationCategory> = [
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
            ),
            UNNotificationCategory(
                identifier: NotificationCategory.speedDrop.rawValue,
                actions: [testAgainAction, dismissAction],
                intentIdentifiers: []
            )
        ]

        center.setNotificationCategories(categories)
    }

    /// Locale-aware number with one decimal, e.g. "12.5" or "12,5".
    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
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

}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier

        await MainActor.run {
            guard let destination = Self.destination(forAction: action, category: category) else { return }
            AppRouter.shared.open(destination)
        }
    }

    /// Where a tapped notification or one of its action buttons should lead.
    static func destination(forAction action: String, category: String) -> AppDestination? {
        switch action {
        case NotificationAction.dismiss.rawValue, UNNotificationDismissActionIdentifier:
            return nil
        case NotificationAction.reviewUsage.rawValue:
            return .usage
        case NotificationAction.retry.rawValue:
            // Home shows the live connection state, which refreshes on resume.
            return .home
        case NotificationAction.testAgain.rawValue:
            return .speedTest
        default:
            // Plain tap on the notification, or "Open App".
            switch category {
            case NotificationCategory.dataLimit.rawValue: return .usage
            case NotificationCategory.speedPeak.rawValue: return .graph
            default: return .home
            }
        }
    }
}

private enum NotificationType: String {
    case disconnect
    case dataLimit
    case speedPeak
    case speedDrop
}

private enum NotificationCategory: String {
    case disconnect = "network.disconnect"
    case dataLimit = "network.data.limit"
    case speedPeak = "network.speed.peak"
    case speedDrop = "network.speed.drop"
}

private enum NotificationAction: String {
    case openApp = "network.action.open"
    case dismiss = "network.action.dismiss"
    case reviewUsage = "network.action.reviewUsage"
    case retry = "network.action.retry"
    case testAgain = "network.action.testAgain"
}
