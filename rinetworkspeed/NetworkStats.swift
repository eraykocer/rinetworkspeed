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
#if canImport(UIKit)
import UIKit
#endif
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
    private var monitorStartDate: Date?
    /// Flag to prevent concurrent startLiveActivity calls while the async
    /// request is still in flight.
    private var isStartingLiveActivity: Bool = false
    /// Dedicated timer that pushes speed updates to the Live Activity at
    /// a cadence ActivityKit can handle (~1 update/second).
    private var liveActivityTimer: Timer?
    /// The currently in-flight Live Activity update task. Cancelled before
    /// a new update is dispatched so we never pile up concurrent updates.
    private var pendingLiveActivityUpdate: Task<Void, Never>?
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var backgroundExpirationWorkItem: DispatchWorkItem?
    private let backgroundLiveActivityGracePeriod: TimeInterval = 25
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

        let isResume = monitorStartDate != nil

        if !isResume {
            history = []
            monitorStartDate = Date()
        }

        // Always take a fresh snapshot so the first sample after resume
        // doesn't produce a huge spike from the accumulated background delta.
        lastSnapshot = currentSnapshot()
        lastSampleDate = Date()
        startPathMonitor()
        applyLiveActivitySetting()
        restartSamplingTimer()
        startLiveActivityTimer()
    }

    /// Lightweight pause: stops only the sampling timer and path monitor.
    /// The Live Activity stays alive so the Dynamic Island keeps showing
    /// the last known speeds instead of disappearing.
    /// Call `start()` to resume — it will detect the existing session and
    /// skip resetting history / monitorStartDate.
    func stopSampling() {
        updateLiveActivity()
        timer?.invalidate()
        timer = nil
        stopLiveActivityTimer(cancelPendingUpdate: false)
        stopPathMonitor()
        saveLatestSpeedsToSharedDefaults()
        // Keep lastSnapshot nil so start() takes a fresh baseline and avoids
        // a giant spike from bytes accumulated while suspended.
        lastSnapshot = nil
        lastSampleDate = nil
    }

    /// Full stop: tears down everything including the Live Activity.
    func stop() {
        timer?.invalidate()
        timer = nil
        stopLiveActivityTimer()
        endBackgroundLiveActivityTask()
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
        monitorStartDate = nil
    }

    func prepareForBackground() {
        guard isLiveActivityEnabled else {
            stopSampling()
            return
        }

        guard timer != nil || liveActivityTimer != nil else {
            saveLatestSpeedsToSharedDefaults()
            updateLiveActivity()
            return
        }

        saveLatestSpeedsToSharedDefaults()
        updateLiveActivity()
        startBackgroundLiveActivityTaskIfNeeded()
    }

    func resumeFromBackground() {
        endBackgroundLiveActivityTask()
        start()
        applyLiveActivitySetting()
    }

    func applyUpdateInterval() {
        guard timer != nil else { return }
        restartSamplingTimer()
    }

    func applyLiveActivitySetting() {
        guard isLiveActivityEnabled else {
            stopLiveActivity()
            stopLiveActivityTimer()
            return
        }

        startLiveActivity()
        startLiveActivityTimer()
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

    /// Returns the download speed for the currently active interface.
    private var activeDownloadSpeed: Double {
        switch activeInterface {
        case .wifi:     return wifiDownloadSpeed
        case .cellular: return cellularDownloadSpeed
        case .none:     return downloadSpeed
        }
    }

    /// Returns the upload speed for the currently active interface.
    private var activeUploadSpeed: Double {
        switch activeInterface {
        case .wifi:     return wifiUploadSpeed
        case .cellular: return cellularUploadSpeed
        case .none:     return uploadSpeed
        }
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

        // If we already have a live activity or one is being started, skip.
        if liveActivity != nil { return }
        guard !isStartingLiveActivity else { return }

        // Try to reclaim an orphaned activity from a previous session first.
        if let existing = Activity<NetworkSpeedAttributes>.activities.first {
            liveActivity = existing
            observePushTokenUpdates()
            // Immediately push current speeds to the reclaimed activity.
            updateLiveActivity()
            return
        }

        isStartingLiveActivity = true

        let attributes = NetworkSpeedAttributes()
        let initialState = NetworkSpeedAttributes.ContentState(
            downloadSpeed: activeDownloadSpeed,
            uploadSpeed: activeUploadSpeed
        )

        Task {
            defer { isStartingLiveActivity = false }

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
                    observePushTokenUpdates()
                    print("Live Activity started without push token fallback.")
                } catch {
                    print("Live Activity request failed: \(error.localizedDescription)")
                    liveActivity = nil
                }
            }
        }
    }

    /// Starts a dedicated 1-second timer that pushes current speeds to the
    /// Live Activity. Using a separate cadence from the sampling timer
    /// prevents overwhelming ActivityKit with too-frequent updates.
    private func startLiveActivityTimer() {
        guard isLiveActivityEnabled else { return }
        guard liveActivityTimer == nil else { return }
        liveActivityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pushLiveActivityUpdate()
        }
    }

    private func stopLiveActivityTimer(cancelPendingUpdate: Bool = true) {
        liveActivityTimer?.invalidate()
        liveActivityTimer = nil
        if cancelPendingUpdate {
            pendingLiveActivityUpdate?.cancel()
            pendingLiveActivityUpdate = nil
        }
    }

    private func startBackgroundLiveActivityTaskIfNeeded() {
        guard backgroundTaskIdentifier == .invalid else { return }

        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(
            withName: "Network speed Live Activity updates"
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.finishBackgroundLiveActivityUpdates()
            }
        }

        guard backgroundTaskIdentifier != .invalid else {
            stopSampling()
            return
        }

        let expirationWorkItem = DispatchWorkItem { [weak self] in
            self?.finishBackgroundLiveActivityUpdates()
        }
        backgroundExpirationWorkItem = expirationWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + backgroundLiveActivityGracePeriod,
            execute: expirationWorkItem
        )
    }

    private func finishBackgroundLiveActivityUpdates() {
        updateLiveActivity()
        stopSampling()
        endBackgroundLiveActivityTask()
    }

    private func endBackgroundLiveActivityTask() {
        backgroundExpirationWorkItem?.cancel()
        backgroundExpirationWorkItem = nil

        guard backgroundTaskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
    }

    /// Called by the dedicated Live Activity timer (~1 Hz). Cancels any
    /// in-flight update task first so we never pile up concurrent requests.
    private func pushLiveActivityUpdate() {
        guard #available(iOS 16.1, *) else { return }
        guard isLiveActivityEnabled else { return }

        // If we don't have a reference yet, try to find an existing activity.
        if liveActivity == nil {
            liveActivity = Activity<NetworkSpeedAttributes>.activities.first
        }

        guard let activity = liveActivity else { return }

        // Check the activity is still active; if it ended, clean up reference.
        if #available(iOS 16.2, *) {
            if activity.activityState == .ended || activity.activityState == .dismissed {
                liveActivity = nil
                // Try to restart the activity on the next timer tick.
                isStartingLiveActivity = false
                startLiveActivity()
                return
            }
        }

        let updatedState = NetworkSpeedAttributes.ContentState(
            downloadSpeed: activeDownloadSpeed,
            uploadSpeed: activeUploadSpeed
        )

        // Cancel the previous in-flight update to avoid piling up Tasks.
        pendingLiveActivityUpdate?.cancel()
        pendingLiveActivityUpdate = Task {
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: updatedState, staleDate: nil)
                await activity.update(content)
            } else {
                await activity.update(using: updatedState)
            }
        }
    }

    /// Public convenience kept for call-sites that need a single immediate
    /// push (e.g. right after reclaiming an orphaned activity).
    func updateLiveActivity() {
        pushLiveActivityUpdate()
    }

    func stopLiveActivity() {
        guard #available(iOS 16.1, *) else { return }

        let allActivities = Activity<NetworkSpeedAttributes>.activities
        guard !allActivities.isEmpty || liveActivity != nil else { return }

        let finalState = NetworkSpeedAttributes.ContentState(
            downloadSpeed: activeDownloadSpeed,
            uploadSpeed: activeUploadSpeed
        )

        pushTokenTask?.cancel()
        pushTokenTask = nil
        liveActivity = nil
        isStartingLiveActivity = false

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
            // Live Activity is updated by its own dedicated timer;
            // no need to call updateLiveActivity() here.
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(previousDate)

        guard elapsed > 0 else {
            lastSampleDate = now
            appendHistorySample(at: now)
            saveLatestSpeedsToSharedDefaults()
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
        // Live Activity is updated by its own dedicated 1 Hz timer.
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
