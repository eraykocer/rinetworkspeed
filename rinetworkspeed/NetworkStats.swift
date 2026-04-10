//
//  NetworkStats.swift
//  rinetworkspeed
//
//  Created by Eray Koçer on 9.04.2026.
//

import Foundation
import Combine
import Darwin
import ActivityKit
import Network
#if canImport(WidgetKit)
import WidgetKit
#endif

struct NetworkSnapshot {
    let bytesIn: UInt64
    let bytesOut: UInt64
    let wifiBytesIn: UInt64
    let wifiBytesOut: UInt64
    let cellularBytesIn: UInt64
    let cellularBytesOut: UInt64
}

struct SpeedSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let downloadSpeed: Double
    let uploadSpeed: Double
}

@available(iOS 16.1, *)
struct NetworkSpeedAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var downloadSpeed: Double
        var uploadSpeed: Double
    }

    var title: String = "Network Speed"
}

enum NetworkInterface: String {
    case wifi
    case cellular
    case none
}

final class NetworkStatsMonitor: ObservableObject {
    var downloadSpeed: Double = 0
    var uploadSpeed: Double = 0
    var wifiDownloadSpeed: Double = 0
    var wifiUploadSpeed: Double = 0
    var cellularDownloadSpeed: Double = 0
    var cellularUploadSpeed: Double = 0
    @Published var activeInterface: NetworkInterface = .none
    @Published var history: [SpeedSample] = []
    @Published var connectionName: String = "Offline"
    @Published var latencyMs: Double?
    @Published var ipAddress: String = "--"
    @Published var wifiSignalDescription: String = "Unavailable"

    private var timer: Timer?
    private var lastSnapshot: NetworkSnapshot?
    private var lastSampleDate: Date?
    private var lastWidgetReloadDate: Date = .distantPast
    private let sharedDefaults = UserDefaults(suiteName: "group.com.rinetworkspeed")
    private let settingsDefaults = UserDefaults.standard
    private let maxHistoryDuration: TimeInterval = 30 * 60
    private var pushTokenTask: Task<Void, Never>?
    private var settingsObserver: AnyCancellable?
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.rinetworkspeed.pathmonitor")
    private let latencyQueue = DispatchQueue(label: "com.rinetworkspeed.latency")
    private let notificationManager = NotificationManager.shared
    private var lastAppliedUpdateInterval: TimeInterval = 0.5
    private var lastAppliedSpeedUnit: String = "bytes"
    private var lastAppliedLiveActivityEnabled: Bool = true
    private var lastDetailsRefreshDate: Date = .distantPast
    private var lastLiveActivityUpdateDate: Date = .distantPast
    private var monitorStartDate: Date?
    @available(iOS 16.1, *)
    private var liveActivity: Activity<NetworkSpeedAttributes>?

    init() {
        lastAppliedUpdateInterval = currentUpdateInterval
        lastAppliedSpeedUnit = currentSpeedUnit
        lastAppliedLiveActivityEnabled = isLiveActivityEnabled
        observeSettingsChanges()
    }

    deinit {
        stop()
        settingsObserver?.cancel()
    }

    func start() {
        guard timer == nil else { return }

        history = []
        monitorStartDate = Date()
        lastSnapshot = currentSnapshot()
        lastSampleDate = Date()
        startPathMonitor()
        applyLiveActivitySetting()
        restartSamplingTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pushTokenTask?.cancel()
        pushTokenTask = nil
        objectWillChange.send()
        downloadSpeed = 0
        uploadSpeed = 0
        wifiDownloadSpeed = 0
        wifiUploadSpeed = 0
        cellularDownloadSpeed = 0
        cellularUploadSpeed = 0
        activeInterface = .none
        connectionName = "Offline"
        latencyMs = nil
        ipAddress = "--"
        wifiSignalDescription = "Unavailable"
        history = []
        stopPathMonitor()
        saveLatestSpeedsToSharedDefaults()
        stopLiveActivity()
        lastSnapshot = nil
        lastSampleDate = nil
    }

    func applyUpdateInterval() {
        guard timer != nil else { return }
        restartSamplingTimer()
    }

    func applyLiveActivitySetting() {
        guard isLiveActivityEnabled else {
            stopLiveActivity()
            return
        }

        startLiveActivity()
        updateLiveActivity()
    }

    func activeDuration() -> TimeInterval {
        guard let monitorStartDate else { return 0 }
        return Date().timeIntervalSince(monitorStartDate)
    }

    private func startPathMonitor() {
        guard pathMonitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            let interface: NetworkInterface
            if isConnected && path.usesInterfaceType(.wifi) {
                interface = .wifi
            } else if isConnected && path.usesInterfaceType(.cellular) {
                interface = .cellular
            } else {
                interface = .none
            }

            DispatchQueue.main.async {
                self?.notificationManager.checkDisconnect(isConnected: isConnected)
                self?.activeInterface = interface
                self?.connectionName = self?.displayName(for: interface) ?? "Offline"
            }
        }
        monitor.start(queue: pathMonitorQueue)
        pathMonitor = monitor
    }

    private func stopPathMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec.isFinite, bytesPerSec >= 0 else {
            return isBitsUnitEnabled ? "0 bps" : "0 B/s"
        }

        let units = isBitsUnitEnabled
            ? ["bps", "Kbps", "Mbps", "Gbps", "Tbps"]
            : ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var value = isBitsUnitEnabled ? bytesPerSec * 8 : bytesPerSec
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f %@", value, units[unitIndex])
        }

        return String(format: "%.1f %@", value, units[unitIndex])
    }

    func formattedSpeedComponents(_ bytesPerSec: Double) -> (value: String, unit: String) {
        guard bytesPerSec.isFinite, bytesPerSec >= 0 else {
            return isBitsUnitEnabled ? ("0", "bps") : ("0", "B/s")
        }

        let units = isBitsUnitEnabled
            ? ["bps", "Kbps", "Mbps", "Gbps", "Tbps"]
            : ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var value = isBitsUnitEnabled ? bytesPerSec * 8 : bytesPerSec
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        let formattedValue = unitIndex == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)

        return (formattedValue, units[unitIndex])
    }

    private var currentUpdateInterval: TimeInterval {
        settingsDefaults.double(forKey: "updateInterval") > 0
            ? settingsDefaults.double(forKey: "updateInterval")
            : 0.5
    }

    private var currentSpeedUnit: String {
        settingsDefaults.string(forKey: "speedUnit") ?? "bytes"
    }

    private var isBitsUnitEnabled: Bool {
        currentSpeedUnit == "bits"
    }

    private var isLiveActivityEnabled: Bool {
        if settingsDefaults.object(forKey: "liveActivityEnabled") == nil {
            return true
        }
        return settingsDefaults.bool(forKey: "liveActivityEnabled")
    }

    private func restartSamplingTimer() {
        timer?.invalidate()
        lastAppliedUpdateInterval = currentUpdateInterval
        timer = Timer.scheduledTimer(withTimeInterval: currentUpdateInterval, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSettingsChange()
            }
    }

    private func handleSettingsChange() {
        let newUpdateInterval = currentUpdateInterval
        let newSpeedUnit = currentSpeedUnit
        let newLiveActivityEnabled = isLiveActivityEnabled

        if timer != nil, newUpdateInterval != lastAppliedUpdateInterval {
            restartSamplingTimer()
        }

        if newSpeedUnit != lastAppliedSpeedUnit {
            lastAppliedSpeedUnit = newSpeedUnit
            objectWillChange.send()
        }

        if newLiveActivityEnabled != lastAppliedLiveActivityEnabled {
            lastAppliedLiveActivityEnabled = newLiveActivityEnabled
            applyLiveActivitySetting()
        }
    }

    private func saveLatestSpeedsToSharedDefaults() {
        sharedDefaults?.set(downloadSpeed, forKey: "downloadSpeed")
        sharedDefaults?.set(uploadSpeed, forKey: "uploadSpeed")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "lastUpdated")
        requestWidgetReloadIfNeeded()
    }

    private func requestWidgetReloadIfNeeded() {
#if canImport(WidgetKit)
        let now = Date()
        guard now.timeIntervalSince(lastWidgetReloadDate) >= 15 else { return }
        lastWidgetReloadDate = now
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rinetworkspeed.NetworkWidget")
#endif
    }

    func startLiveActivity() {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard isLiveActivityEnabled else { return }
        guard liveActivity == nil else { return }

        let attributes = NetworkSpeedAttributes()
        let initialState = NetworkSpeedAttributes.ContentState(
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed
        )

        Task {
            do {
                if #available(iOS 16.2, *) {
                    let content = ActivityContent(state: initialState, staleDate: nil)
                    liveActivity = try Activity<NetworkSpeedAttributes>.request(
                        attributes: attributes,
                        content: content,
                        pushType: .token
                    )
                } else {
                    liveActivity = try Activity<NetworkSpeedAttributes>.request(
                        attributes: attributes,
                        contentState: initialState,
                        pushType: .token
                    )
                }
                observePushTokenUpdates()
            } catch {
                print("Live Activity request with push token failed: \(error.localizedDescription)")

                do {
                    if #available(iOS 16.2, *) {
                        let content = ActivityContent(state: initialState, staleDate: nil)
                        liveActivity = try Activity<NetworkSpeedAttributes>.request(
                            attributes: attributes,
                            content: content,
                            pushType: nil
                        )
                    } else {
                        liveActivity = try Activity<NetworkSpeedAttributes>.request(
                            attributes: attributes,
                            contentState: initialState,
                            pushType: nil
                        )
                    }
                    print("Live Activity started without push token fallback.")
                } catch {
                    print("Live Activity request failed: \(error.localizedDescription)")
                    liveActivity = nil
                }
            }
        }
    }

    func updateLiveActivity() {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard isLiveActivityEnabled else { return }

        let now = Date()
        guard now.timeIntervalSince(lastLiveActivityUpdateDate) >= 0.5 else { return }
        lastLiveActivityUpdateDate = now

        if liveActivity == nil {
            liveActivity = Activity<NetworkSpeedAttributes>.activities.first
        }

        guard let activity = liveActivity else { return }

        let updatedState = NetworkSpeedAttributes.ContentState(
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed
        )

        Task {
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: updatedState, staleDate: nil)
                await activity.update(content)
            } else {
                await activity.update(using: updatedState)
            }
        }
    }

    func stopLiveActivity() {
        guard #available(iOS 16.1, *) else { return }

        let allActivities = Activity<NetworkSpeedAttributes>.activities
        guard !allActivities.isEmpty || liveActivity != nil else { return }

        let finalState = NetworkSpeedAttributes.ContentState(
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed
        )

        pushTokenTask?.cancel()
        pushTokenTask = nil
        liveActivity = nil

        Task {
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: finalState, staleDate: nil)
                for activity in allActivities {
                    await activity.end(content, dismissalPolicy: .immediate)
                }
            } else {
                for activity in allActivities {
                    await activity.end(using: finalState, dismissalPolicy: .immediate)
                }
            }
        }
    }

    private func observePushTokenUpdates() {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = liveActivity else { return }

        pushTokenTask?.cancel()
        pushTokenTask = Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                sharedDefaults?.set(token, forKey: "liveActivityPushToken")
                print("Live Activity push token: \(token)")
            }
        }
    }

    private func sample() {
        guard
            let previousSnapshot = lastSnapshot,
            let previousDate = lastSampleDate
        else {
            lastSnapshot = currentSnapshot()
            lastSampleDate = Date()
            appendHistorySample(at: Date())
            saveLatestSpeedsToSharedDefaults()
            updateLiveActivity()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(previousDate)

        guard elapsed > 0 else {
            lastSampleDate = now
            appendHistorySample(at: now)
            saveLatestSpeedsToSharedDefaults()
            updateLiveActivity()
            return
        }

        let snapshot = currentSnapshot()

        let bytesInDelta = snapshot.bytesIn >= previousSnapshot.bytesIn
            ? snapshot.bytesIn - previousSnapshot.bytesIn
            : 0

        let bytesOutDelta = snapshot.bytesOut >= previousSnapshot.bytesOut
            ? snapshot.bytesOut - previousSnapshot.bytesOut
            : 0

        let wifiBytesInDelta = snapshot.wifiBytesIn >= previousSnapshot.wifiBytesIn
            ? snapshot.wifiBytesIn - previousSnapshot.wifiBytesIn
            : 0

        let wifiBytesOutDelta = snapshot.wifiBytesOut >= previousSnapshot.wifiBytesOut
            ? snapshot.wifiBytesOut - previousSnapshot.wifiBytesOut
            : 0

        let cellularBytesInDelta = snapshot.cellularBytesIn >= previousSnapshot.cellularBytesIn
            ? snapshot.cellularBytesIn - previousSnapshot.cellularBytesIn
            : 0

        let cellularBytesOutDelta = snapshot.cellularBytesOut >= previousSnapshot.cellularBytesOut
            ? snapshot.cellularBytesOut - previousSnapshot.cellularBytesOut
            : 0

        objectWillChange.send()
        downloadSpeed = Double(bytesInDelta) / elapsed
        uploadSpeed = Double(bytesOutDelta) / elapsed
        wifiDownloadSpeed = Double(wifiBytesInDelta) / elapsed
        wifiUploadSpeed = Double(wifiBytesOutDelta) / elapsed
        cellularDownloadSpeed = Double(cellularBytesInDelta) / elapsed
        cellularUploadSpeed = Double(cellularBytesOutDelta) / elapsed

        let currentThroughput = max(downloadSpeed, uploadSpeed)
        notificationManager.checkSpeedDrop(current: currentThroughput)
        notificationManager.checkSpeedPeak(current: currentThroughput)

        appendHistorySample(at: now)
        refreshConnectionDetailsIfNeeded(at: now)
        saveLatestSpeedsToSharedDefaults()
        updateLiveActivity()
        #if os(iOS)
        WatchConnectivityManager.shared.updateSpeeds(
            download: downloadSpeed,
            upload: uploadSpeed,
            activeInterface: activeInterface
        )
        #endif

        lastSnapshot = snapshot
        lastSampleDate = now
    }

    private func appendHistorySample(at timestamp: Date) {
        history.append(
            SpeedSample(
                timestamp: timestamp,
                downloadSpeed: downloadSpeed,
                uploadSpeed: uploadSpeed
            )
        )

        let cutoff = timestamp.addingTimeInterval(-maxHistoryDuration)
        history.removeAll { $0.timestamp < cutoff }
    }

    private func refreshConnectionDetailsIfNeeded(at now: Date) {
        guard now.timeIntervalSince(lastDetailsRefreshDate) >= 5 else { return }
        lastDetailsRefreshDate = now
        ipAddress = currentIPAddress()
        wifiSignalDescription = activeInterface == .wifi ? "Connected" : "Unavailable"
        measureLatency()
    }

    private func measureLatency() {
        let start = Date()
        let connection = NWConnection(host: "8.8.8.8", port: 53, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let latency = Date().timeIntervalSince(start) * 1000
                DispatchQueue.main.async {
                    self?.latencyMs = latency
                }
                connection.cancel()
            case .failed:
                DispatchQueue.main.async {
                    self?.latencyMs = nil
                }
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: latencyQueue)
    }

    private func currentIPAddress() -> String {
        var address: String = "--"
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else {
            return address
        }

        defer {
            freeifaddrs(first)
        }

        var pointer = first
        let preferredInterface = activeInterface == .cellular ? "pdp_ip0" : "en0"

        while true {
            let interface = pointer.pointee
            if interface.ifa_addr != nil, interface.ifa_addr.pointee.sa_family == UInt8(AF_INET), let name = interface.ifa_name {
                let interfaceName = String(cString: name)
                if interfaceName == preferredInterface {
                    var hostName = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostName,
                        socklen_t(hostName.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostName)
                    break
                }
            }

            guard let next = interface.ifa_next else { break }
            pointer = next
        }

        return address
    }

    private func displayName(for interface: NetworkInterface) -> String {
        switch interface {
        case .wifi:
            return "WiFi"
        case .cellular:
            return "Cellular"
        case .none:
            return "Offline"
        }
    }

    private func currentSnapshot() -> NetworkSnapshot {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var wifiIn: UInt64 = 0
        var wifiOut: UInt64 = 0
        var cellularIn: UInt64 = 0
        var cellularOut: UInt64 = 0

        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else {
            return NetworkSnapshot(
                bytesIn: 0,
                bytesOut: 0,
                wifiBytesIn: 0,
                wifiBytesOut: 0,
                cellularBytesIn: 0,
                cellularBytesOut: 0
            )
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
                if name == "lo0" {
                    guard let next = interface.ifa_next else { break }
                    pointer = next
                    continue
                }

                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                let inBytes = UInt64(networkData.ifi_ibytes)
                let outBytes = UInt64(networkData.ifi_obytes)

                if name == "en0" {
                    wifiIn += inBytes
                    wifiOut += outBytes
                } else if name.hasPrefix("pdp_ip") {
                    cellularIn += inBytes
                    cellularOut += outBytes
                }
            }

            guard let next = interface.ifa_next else { break }
            pointer = next
        }

        totalIn = wifiIn + cellularIn
        totalOut = wifiOut + cellularOut

        return NetworkSnapshot(
            bytesIn: totalIn,
            bytesOut: totalOut,
            wifiBytesIn: wifiIn,
            wifiBytesOut: wifiOut,
            cellularBytesIn: cellularIn,
            cellularBytesOut: cellularOut
        )
    }
}
