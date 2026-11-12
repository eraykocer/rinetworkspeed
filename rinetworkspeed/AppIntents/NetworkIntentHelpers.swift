//
//  NetworkIntentHelpers.swift
//  rinetworkspeed
//
//  Shared helpers used by all network AppIntents.
//  Keeps a light copy of the getifaddrs snapshot so intents stay self-contained.
//

import Foundation
import Darwin

// MARK: - Raw network I/O snapshot

struct RawNetworkSnapshot {
    let bytesIn:  UInt64
    let bytesOut: UInt64
}

/// Reads the kernel counters for all non-loopback AF_LINK interfaces.
func captureNetworkSnapshot() -> RawNetworkSnapshot {
    var addrs: UnsafeMutablePointer<ifaddrs>?
    var totalIn:  UInt64 = 0
    var totalOut: UInt64 = 0

    guard getifaddrs(&addrs) == 0, let firstAddr = addrs else {
        return RawNetworkSnapshot(bytesIn: 0, bytesOut: 0)
    }
    defer { freeifaddrs(firstAddr) }

    var ptr = firstAddr
    while true {
        let iface = ptr.pointee
        if
            let namePtr = iface.ifa_name,
            let data    = iface.ifa_data,
            iface.ifa_addr != nil,
            iface.ifa_addr.pointee.sa_family == UInt8(AF_LINK)
        {
            let name = String(cString: namePtr)
            if name != "lo0" {
                let nd     = data.assumingMemoryBound(to: if_data.self).pointee
                totalIn   += UInt64(nd.ifi_ibytes)
                totalOut  += UInt64(nd.ifi_obytes)
            }
        }
        guard let next = iface.ifa_next else { break }
        ptr = next
    }
    return RawNetworkSnapshot(bytesIn: totalIn, bytesOut: totalOut)
}

// MARK: - Formatters

func formatIntentSpeed(_ bytesPerSec: Double) -> String {
    guard bytesPerSec.isFinite, bytesPerSec >= 0 else { return "0 B/s" }
    let units = ["B/s", "KB/s", "MB/s", "GB/s"]
    var value = bytesPerSec
    var idx   = 0
    while value >= 1_024, idx < units.count - 1 { value /= 1_024; idx += 1 }
    return idx == 0
        ? value.fixed(0) + " " + units[idx]
        : value.fixed(1) + " " + units[idx]
}

func formatIntentBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle   = .binary
    formatter.isAdaptive   = true
    return formatter.string(fromByteCount: Int64(bytes))
}
