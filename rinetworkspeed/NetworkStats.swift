//
//  NetworkStats.swift
//  rinetworkspeed
//
//  Created by Eray Koçer on 9.04.2026.
//

import Foundation
import Darwin

struct NetworkSnapshot {
    let bytesIn: UInt64
    let bytesOut: UInt64
}

final class NetworkStatsMonitor: ObservableObject {
    @Published var downloadSpeed: Double = 0
    @Published var uploadSpeed: Double = 0

    private var timer: Timer?
    private var lastSnapshot: NetworkSnapshot?
    private var lastSampleDate: Date?

    deinit {
        stop()
    }

    func start() {
        guard timer == nil else { return }

        lastSnapshot = currentSnapshot()
        lastSampleDate = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastSnapshot = nil
        lastSampleDate = nil
        downloadSpeed = 0
        uploadSpeed = 0
    }

    func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec.isFinite, bytesPerSec >= 0 else {
            return "0 B/s"
        }

        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var value = bytesPerSec
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

    private func sample() {
        guard
            let previousSnapshot = lastSnapshot,
            let previousDate = lastSampleDate
        else {
            lastSnapshot = currentSnapshot()
            lastSampleDate = Date()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(previousDate)

        guard elapsed > 0 else {
            lastSampleDate = now
            return
        }

        let snapshot = currentSnapshot()

        let bytesInDelta = snapshot.bytesIn >= previousSnapshot.bytesIn
            ? snapshot.bytesIn - previousSnapshot.bytesIn
            : 0

        let bytesOutDelta = snapshot.bytesOut >= previousSnapshot.bytesOut
            ? snapshot.bytesOut - previousSnapshot.bytesOut
            : 0

        downloadSpeed = Double(bytesInDelta) / elapsed
        uploadSpeed = Double(bytesOutDelta) / elapsed

        lastSnapshot = snapshot
        lastSampleDate = now
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
                interface.ifa_addr != nil,
                interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK)
            {
                let name = String(cString: namePtr)
                if name != "lo0" {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalIn += UInt64(networkData.ifi_ibytes)
                    totalOut += UInt64(networkData.ifi_obytes)
                }
            }

            guard let next = interface.ifa_next else { break }
            pointer = next
        }

        return NetworkSnapshot(bytesIn: totalIn, bytesOut: totalOut)
    }
}
