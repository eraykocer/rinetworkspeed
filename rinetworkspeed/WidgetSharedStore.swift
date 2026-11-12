//
//  WidgetSharedStore.swift
//  rinetworkspeed
//
//  Writes the values the widget extension shows into the shared App Group.
//  Widgets cannot measure anything live, so they display the last speed test
//  and the usage counters as of the last time the app ran.
//
//  Keys must stay in sync with `WidgetSnapshot` in
//  NetworkWidget/NetworkStatusWidget.swift.
//

import Foundation
import WidgetKit

enum WidgetSharedStore {
    static let suiteName = "group.rinetworkspeedapp"
    static let statusWidgetKind = "NetworkStatusWidget"
    static let usageWidgetKind = "DataUsageWidget"

    enum Key {
        static let lastTestDate = "widgetLastTestDate"
        static let lastTestDownload = "widgetLastTestDownload"
        static let lastTestUpload = "widgetLastTestUpload"
        static let lastTestPing = "widgetLastTestPing"
        /// Also read by `GetDataUsageIntent`.
        static let todayWifi = "intentTodayWifi"
        static let todayCellular = "intentTodayCellular"
        static let usageUpdatedAt = "widgetUsageUpdatedAt"
        static let periodCellular = "widgetPeriodCellular"
        static let periodEnd = "widgetPeriodEnd"
        static let limitGB = "widgetLimitGB"
        static let limitEnabled = "widgetLimitEnabled"
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func saveLastSpeedTest(_ result: SpeedTestResult) {
        guard let defaults else { return }
        defaults.set(result.date.timeIntervalSince1970, forKey: Key.lastTestDate)
        defaults.set(result.downloadSpeed, forKey: Key.lastTestDownload)
        defaults.set(result.uploadSpeed, forKey: Key.lastTestUpload)
        defaults.set(result.ping, forKey: Key.lastTestPing)
        reloadWidgets()
    }

    static func saveTodayUsage(wifi: UInt64, cellular: UInt64) {
        guard let defaults else { return }
        defaults.set(Int(clamping: wifi), forKey: Key.todayWifi)
        defaults.set(Int(clamping: cellular), forKey: Key.todayCellular)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.usageUpdatedAt)
    }

    /// Cellular usage in the current billing period and the limit it is measured against.
    static func savePeriodUsage(cellular: UInt64, periodEnd: Date, limitGB: Double, limitEnabled: Bool) {
        guard let defaults else { return }
        defaults.set(Int(clamping: cellular), forKey: Key.periodCellular)
        defaults.set(periodEnd.timeIntervalSince1970, forKey: Key.periodEnd)
        defaults.set(limitGB, forKey: Key.limitGB)
        defaults.set(limitEnabled, forKey: Key.limitEnabled)
    }

    /// Usage is written every few seconds, so widgets are reloaded only when
    /// the app goes to the background instead of on every write.
    static func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: statusWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: usageWidgetKind)
    }
}
