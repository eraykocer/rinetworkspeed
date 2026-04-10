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

    private struct BaselineSnapshot: Codable {
        let dateKey: String
        let wifiBytes: UInt64
        let cellularBytes: UInt64
    }

    private typealias DailyTotals = [String: (wifi: UInt64, cellular: UInt64)]

    private let defaults = UserDefaults.standard
    private let baselineKey = "dataUsageBaselineSnapshot"
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

    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }

    func usageForCurrentMonth() -> [DailyUsageSample] {
        let now = Date()
        guard let monthRange = calendar.dateInterval(of: .month, for: now) else { return [] }

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
        let currentUsage = currentCumulativeUsage()
        let todayKey = dateKey(for: Date())
        let baseline = BaselineSnapshot(
            dateKey: todayKey,
            wifiBytes: currentUsage.wifiBytes,
            cellularBytes: currentUsage.cellularBytes
        )
        saveBaseline(baseline)
        dailyTotals[todayKey] = (wifi: 0, cellular: 0)
        todayWifiBytes = 0
        todayCellularBytes = 0
        saveDailyTotals()
        recalculateWeeklyTotals()
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
        let currentUsage = currentCumulativeUsage()
        let baseline = ensureBaseline(for: currentUsage)

        let todayWifi = currentUsage.wifiBytes >= baseline.wifiBytes ? currentUsage.wifiBytes - baseline.wifiBytes : 0
        let todayCellular = currentUsage.cellularBytes >= baseline.cellularBytes ? currentUsage.cellularBytes - baseline.cellularBytes : 0

        todayWifiBytes = todayWifi
        todayCellularBytes = todayCellular

        let todayKey = dateKey(for: Date())
        dailyTotals[todayKey] = (wifi: todayWifi, cellular: todayCellular)
        saveDailyTotals()

        if defaults.bool(forKey: "dataLimitEnabled") {
            let totalUsedGB = Double(todayWifi + todayCellular) / 1_073_741_824
            let limitGB = max(defaults.double(forKey: "dataLimitGB"), 0)
            notificationManager.checkDataLimit(usedGB: totalUsedGB, limitGB: limitGB)
        }

        recalculateWeeklyTotals()
    }

    private func recalculateWeeklyTotals() {
        let samples = usageForLast7Days()
        weeklyWifiBytes = samples.reduce(0) { $0 + $1.wifiBytes }
        weeklyCellularBytes = samples.reduce(0) { $0 + $1.cellularBytes }
    }

    private func ensureBaseline(for usage: (wifiBytes: UInt64, cellularBytes: UInt64)) -> BaselineSnapshot {
        let todayKey = dateKey(for: Date())

        if let baseline = loadBaseline(), baseline.dateKey == todayKey {
            return baseline
        }

        let baseline = BaselineSnapshot(
            dateKey: todayKey,
            wifiBytes: usage.wifiBytes,
            cellularBytes: usage.cellularBytes
        )
        saveBaseline(baseline)
        return baseline
    }

    private func loadBaseline() -> BaselineSnapshot? {
        guard let data = defaults.data(forKey: baselineKey) else { return nil }
        return try? JSONDecoder().decode(BaselineSnapshot.self, from: data)
    }

    private func saveBaseline(_ snapshot: BaselineSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: baselineKey)
    }

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
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func date(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    private func currentCumulativeUsage() -> (wifiBytes: UInt64, cellularBytes: UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        var wifiBytes: UInt64 = 0
        var cellularBytes: UInt64 = 0

        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else {
            return (0, 0)
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
                let bytes = UInt64(networkData.ifi_ibytes) + UInt64(networkData.ifi_obytes)

                if name == "en0" {
                    wifiBytes += bytes
                } else if name == "pdp_ip0" {
                    cellularBytes += bytes
                }
            }

            guard let next = interface.ifa_next else { break }
            pointer = next
        }

        return (wifiBytes, cellularBytes)
    }
}
