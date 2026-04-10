import Foundation
import Darwin
import React

private struct NetworkSnapshot {
    let bytesIn: UInt64
    let bytesOut: UInt64
}

@objc(NetworkStatsModule)
final class NetworkStatsModule: RCTEventEmitter {
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.rinetworkspeed.NetworkStatsModule.timer")
    private var lastSnapshot: NetworkSnapshot?
    private var lastSampleTime: TimeInterval?
    private var hasListeners = false

    override init() {
        super.init()
    }

    override static func requiresMainQueueSetup() -> Bool {
        false
    }

    override func supportedEvents() -> [String]! {
        ["NetworkStatsUpdate"]
    }

    override func startObserving() {
        hasListeners = true
    }

    override func stopObserving() {
        hasListeners = false
    }

    @objc(getSnapshot:rejecter:)
    func getSnapshot(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let snapshot = currentSnapshot()
        resolve([
            "bytesIn": snapshot.bytesIn,
            "bytesOut": snapshot.bytesOut
        ])
    }

    @objc(startTimer:)
    func startTimer(_ interval: NSNumber?) {
        let requestedInterval = interval?.doubleValue ?? 0.5
        let effectiveInterval = requestedInterval > 0 ? requestedInterval : 0.5

        stopTimer()

        lastSnapshot = currentSnapshot()
        lastSampleTime = Date().timeIntervalSince1970

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + effectiveInterval, repeating: effectiveInterval)
        timer.setEventHandler { [weak self] in
            self?.sample()
        }

        self.timer = timer
        timer.resume()
    }

    @objc
    func stopTimer() {
        timer?.cancel()
        timer = nil
        lastSnapshot = nil
        lastSampleTime = nil
    }

    private func sample() {
        guard
            let previousSnapshot = lastSnapshot,
            let previousTime = lastSampleTime
        else {
            lastSnapshot = currentSnapshot()
            lastSampleTime = Date().timeIntervalSince1970
            return
        }

        let now = Date().timeIntervalSince1970
        let elapsed = now - previousTime

        guard elapsed > 0 else {
            lastSampleTime = now
            return
        }

        let snapshot = currentSnapshot()

        let bytesInDelta: UInt64 = snapshot.bytesIn >= previousSnapshot.bytesIn
            ? snapshot.bytesIn - previousSnapshot.bytesIn
            : 0

        let bytesOutDelta: UInt64 = snapshot.bytesOut >= previousSnapshot.bytesOut
            ? snapshot.bytesOut - previousSnapshot.bytesOut
            : 0

        let downloadSpeed = Double(bytesInDelta) / elapsed
        let uploadSpeed = Double(bytesOutDelta) / elapsed

        if hasListeners {
            let payload: [String: Any] = [
                "downloadSpeed": downloadSpeed,
                "uploadSpeed": uploadSpeed
            ]

            DispatchQueue.main.async { [weak self] in
                self?.sendEvent(withName: "NetworkStatsUpdate", body: payload)
            }
        }

        lastSnapshot = snapshot
        lastSampleTime = now
    }

    private func currentSnapshot() -> NetworkSnapshot {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else {
            return NetworkSnapshot(bytesIn: 0, bytesOut: 0)
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
                let addr = interface.ifa_addr,
                addr.pointee.sa_family == UInt8(AF_LINK)
            {
                let name = String(cString: namePtr)
                if name != "lo0" {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalIn += UInt64(networkData.ifi_ibytes)
                    totalOut += UInt64(networkData.ifi_obytes)
                }
            }

            guard let next = interface.ifa_next else {
                break
            }
            pointer = next
        }

        return NetworkSnapshot(bytesIn: totalIn, bytesOut: totalOut)
    }
}
