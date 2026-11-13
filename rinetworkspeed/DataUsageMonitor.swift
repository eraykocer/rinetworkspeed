//
//  DataUsageMonitor.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import Foundation
import Combine
import Darwin
import SystemConfiguration

struct DailyUsageSample: Identifiable {
    let id = UUID()
    let date: Date
    let wifiBytes: UInt64
    let cellularBytes: UInt64
}

final class DataUsageMonitor: ObservableObject {
    @Published var todayWifiBytes: UInt64 = 0
    @Published var todayCellularBytes: UInt64 = 0
    @Published var weeklyWifiBytes: UInt64 = 0
    @Published var weeklyCellularBytes: UInt64 = 0
    /// Usage since the start of the current billing period (see `dataLimitResetDay`).
    /// The data limit is a carrier plan limit, so it is compared against cellular only.
    @Published private(set) var periodWifiBytes: UInt64 = 0
    @Published private(set) var periodCellularBytes: UInt64 = 0
    /// False until the first counter sample has been taken, so the UI can show
    /// a loading state only during startup instead of whenever usage is zero.
    @Published private(set) var hasInitialSample = false

    /// Raw interface counters from the previous refresh. The kernel counters
    /// (`if_data.ifi_ibytes/ifi_obytes`) are 32-bit, wrap every ~4 GB and reset
    /// on reboot, so usage is accumulated from deltas between samples rather
    /// than by subtracting a fixed daily baseline (which got stuck at 0 after
    /// a wrap or reboot because the current value dropped below the baseline).
    struct RawCounters: Codable, Equatable {
        let bootTime: TimeInterval
        let wifiIn: UInt32
        let wifiOut: UInt32
        let cellularIn: UInt32
        let cellularOut: UInt32
    }

    private typealias DailyTotals = [String: (wifi: UInt64, cellular: UInt64)]

    private let defaults = UserDefaults.standard
    private let legacyBaselineKey = "dataUsageBaselineSnapshot"
    private let lastRawCountersKey = "dataUsageLastRawCounters"
    private let dailyTotalsKey = "dataUsageDailyTotals"
    private let notificationManager = NotificationManager.shared
    private var dailyTotals: DailyTotals = [:]
    private var timer: Timer?
    private var calendar: Calendar = .current

    deinit {
        stop()
    }

    func start() {
        guard timer == nil else { return }
        loadDailyTotals()
        refreshUsage()

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func usageForLast7Days() -> [DailyUsageSample] {
        let today = calendar.startOfDay(for: Date())

        return (0..<7).reversed().compactMap { offset -> DailyUsageSample? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = dateKey(for: date)
            let usage = dailyTotals[key] ?? (0, 0)
            return DailyUsageSample(date: date, wifiBytes: usage.wifi, cellularBytes: usage.cellular)
        }
    }

    // Formatters are expensive to create; these were rebuilt on every call
    // (several times per UI render and per 5 s refresh).
    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private lazy var dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func formatBytes(_ bytes: UInt64) -> String {
        Self.bytesFormatter.string(fromByteCount: Int64(bytes))
    }

    func usageForCurrentMonth() -> [DailyUsageSample] {
        usageForMonth(Date())
    }

    func usageForMonth(_ monthDate: Date) -> [DailyUsageSample] {
        guard let monthRange = calendar.dateInterval(of: .month, for: monthDate) else { return [] }

        return dailyTotals.compactMap { key, usage in
            guard let date = date(from: key), monthRange.contains(date) else { return nil }
            return DailyUsageSample(date: date, wifiBytes: usage.wifi, cellularBytes: usage.cellular)
        }
        .sorted { $0.date < $1.date }
    }

    func monthlySummary() -> (wifi: UInt64, cellular: UInt64, dailyAverage: UInt64, projectedMonthly: UInt64) {
        let samples = usageForCurrentMonth()
        let wifi = samples.reduce(0) { $0 + $1.wifiBytes }
        let cellular = samples.reduce(0) { $0 + $1.cellularBytes }
        let total = wifi + cellular
        let daysElapsed = max(1, samples.count)
        let dailyAverage = total / UInt64(daysElapsed)
        let projectedMonthly = dailyAverage * 30

        return (wifi, cellular, dailyAverage, projectedMonthly)
    }

    func resetToday() {
        saveLastRawCounters(currentRawCounters())
        let todayKey = dateKey(for: Date())
        dailyTotals[todayKey] = (wifi: 0, cellular: 0)
        todayWifiBytes = 0
        todayCellularBytes = 0
        saveDailyTotals()
        recalculateWeeklyTotals()
        recalculatePeriodTotals()
    }

    /// Reset day chosen in Settings, clamped to 1...28 (0 means "never set").
    private var resetDay: Int {
        min(max(defaults.integer(forKey: "dataLimitResetDay"), 1), 28)
    }

    /// First day of the billing period that contains `date`.
    func billingPeriodStart(resetDay: Int, for date: Date = Date()) -> Date {
        let today = calendar.startOfDay(for: date)
        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = resetDay
        let thisMonthReset = calendar.date(from: components) ?? today

        if today >= thisMonthReset {
            return thisMonthReset
        }
        return calendar.date(byAdding: .month, value: -1, to: thisMonthReset) ?? thisMonthReset
    }

    /// Re-reads the reset day and recomputes the billing-period totals, e.g.
    /// after the user changes the reset day in Settings.
    func recalculatePeriodTotals() {
        let periodStart = billingPeriodStart(resetDay: resetDay)
        var wifi: UInt64 = 0
        var cellular: UInt64 = 0

        for (key, usage) in dailyTotals {
            guard let date = date(from: key), date >= periodStart else { continue }
            wifi += usage.wifi
            cellular += usage.cellular
        }

        if periodWifiBytes != wifi { periodWifiBytes = wifi }
        if periodCellularBytes != cellular { periodCellularBytes = cellular }
    }

    func daysUntilReset(resetDay: Int) -> Int {
        let today = calendar.startOfDay(for: Date())
        let currentDay = calendar.component(.day, from: today)

        if currentDay < resetDay {
            return resetDay - currentDay
        }

        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) else { return 0 }
        let range = calendar.range(of: .day, in: .month, for: nextMonth) ?? 1..<29
        let clampedDay = min(resetDay, range.count)
        var components = calendar.dateComponents([.year, .month], from: nextMonth)
        components.day = clampedDay
        let resetDate = calendar.date(from: components) ?? nextMonth

        return max(0, calendar.dateComponents([.day], from: today, to: resetDate).day ?? 0)
    }

    private func refreshUsage() {
        let current = currentRawCounters()
        let delta = Self.usageDelta(from: loadLastRawCounters(), to: current)
        saveLastRawCounters(current)

        let todayKey = dateKey(for: Date())
        let previous = dailyTotals[todayKey] ?? (wifi: 0, cellular: 0)
        let todayWifi = previous.wifi + delta.wifi
        let todayCellular = previous.cellular + delta.cellular

        dailyTotals[todayKey] = (wifi: todayWifi, cellular: todayCellular)
        saveDailyTotals()

        // Avoid publishing (and re-rendering observers) when nothing changed.
        if todayWifiBytes != todayWifi { todayWifiBytes = todayWifi }
        if todayCellularBytes != todayCellular { todayCellularBytes = todayCellular }
        if !hasInitialSample { hasInitialSample = true }

        #if os(iOS)
        // Persist today's totals to the shared App Group so AppIntents and
        // widgets can read them even when the main app process is not running.
        WidgetSharedStore.saveTodayUsage(wifi: todayWifi, cellular: todayCellular)
        #endif

        recalculateWeeklyTotals()
        recalculatePeriodTotals()

        let periodStart = billingPeriodStart(resetDay: resetDay)
        WidgetSharedStore.savePeriodUsage(
            cellular: periodCellularBytes,
            periodEnd: calendar.date(byAdding: .month, value: 1, to: periodStart) ?? periodStart,
            limitGB: max(defaults.double(forKey: "dataLimitGB"), 0),
            limitEnabled: defaults.bool(forKey: "dataLimitEnabled")
        )

        // Data limit alerts are a Pro feature.
        if defaults.bool(forKey: "dataLimitEnabled") && PurchaseManager.shared.isPro {
            let usedGB = Double(periodCellularBytes) / 1_073_741_824
            let limitGB = max(defaults.double(forKey: "dataLimitGB"), 0)
            notificationManager.checkDataLimit(
                usedGB: usedGB,
                limitGB: limitGB,
                periodID: Self.periodIDFormatter.string(from: periodStart)
            )
        }
    }

    private static let periodIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func recalculateWeeklyTotals() {
        let samples = usageForLast7Days()
        let wifi = samples.reduce(0) { $0 + $1.wifiBytes }
        let cellular = samples.reduce(0) { $0 + $1.cellularBytes }
        if weeklyWifiBytes != wifi { weeklyWifiBytes = wifi }
        if weeklyCellularBytes != cellular { weeklyCellularBytes = cellular }
    }

    /// Bytes transferred between two samples. Within the same boot session a
    /// wrapping 32-bit subtraction handles counter overflow; after a reboot the
    /// counters restarted from zero, so the current value is the delta.
    nonisolated static func usageDelta(from last: RawCounters?, to current: RawCounters) -> (wifi: UInt64, cellular: UInt64) {
        guard let last else { return (0, 0) }

        guard abs(last.bootTime - current.bootTime) < 1 else {
            return (
                UInt64(current.wifiIn) + UInt64(current.wifiOut),
                UInt64(current.cellularIn) + UInt64(current.cellularOut)
            )
        }

        let wifi = UInt64(current.wifiIn &- last.wifiIn) + UInt64(current.wifiOut &- last.wifiOut)
        let cellular = UInt64(current.cellularIn &- last.cellularIn) + UInt64(current.cellularOut &- last.cellularOut)
        return (wifi, cellular)
    }

    private func loadLastRawCounters() -> RawCounters? {
        guard let data = defaults.data(forKey: lastRawCountersKey) else { return nil }
        return try? JSONDecoder().decode(RawCounters.self, from: data)
    }

    private func saveLastRawCounters(_ counters: RawCounters) {
        guard let data = try? JSONEncoder().encode(counters) else { return }
        defaults.set(data, forKey: lastRawCountersKey)
        defaults.removeObject(forKey: legacyBaselineKey)
    }

    private static let systemBootTime: TimeInterval = {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0 else { return 0 }
        return TimeInterval(bootTime.tv_sec) + TimeInterval(bootTime.tv_usec) / 1_000_000
    }()

    private func loadDailyTotals() {
        guard let stored = defaults.dictionary(forKey: dailyTotalsKey) as? [String: [String: UInt64]] else {
            dailyTotals = [:]
            return
        }

        dailyTotals = stored.reduce(into: [:]) { partialResult, element in
            let wifi = element.value["wifi"] ?? 0
            let cellular = element.value["cellular"] ?? 0
            partialResult[element.key] = (wifi: wifi, cellular: cellular)
        }
    }

    private func saveDailyTotals() {
        let serializable = dailyTotals.reduce(into: [String: [String: UInt64]]()) { partialResult, element in
            partialResult[element.key] = [
                "wifi": element.value.wifi,
                "cellular": element.value.cellular
            ]
        }
        defaults.set(serializable, forKey: dailyTotalsKey)
    }

    private func dateKey(for date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    private func date(from key: String) -> Date? {
        dayKeyFormatter.date(from: key)
    }

    private func currentRawCounters() -> RawCounters {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        var wifiIn: UInt32 = 0, wifiOut: UInt32 = 0
        var cellularIn: UInt32 = 0, cellularOut: UInt32 = 0

        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else {
            return RawCounters(bootTime: Self.systemBootTime, wifiIn: 0, wifiOut: 0, cellularIn: 0, cellularOut: 0)
        }

        defer {
            freeifaddrs(firstAddr)
        }

        var pointer = firstAddr

        while true {
            let interface = pointer.pointee

            if
                let namePtr = interface.ifa_name,
                let data = interface.ifa_data,
                interface.ifa_addr != nil,
                interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK)
            {
                let name = String(cString: namePtr)
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee

                if name == "en0" {
                    wifiIn = networkData.ifi_ibytes
                    wifiOut = networkData.ifi_obytes
                } else if name == "pdp_ip0" {
                    cellularIn = networkData.ifi_ibytes
                    cellularOut = networkData.ifi_obytes
                }
            }

            guard let next = interface.ifa_next else { break }
            pointer = next
        }

        return RawCounters(
            bootTime: Self.systemBootTime,
            wifiIn: wifiIn,
            wifiOut: wifiOut,
            cellularIn: cellularIn,
            cellularOut: cellularOut
        )
    }
}
