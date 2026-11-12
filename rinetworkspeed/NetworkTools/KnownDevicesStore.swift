//
//  KnownDevicesStore.swift
//  rinetworkspeed
//
//  Remembers which devices the IP scanner has seen on each network, so a
//  scan can point out devices that were not there before.
//
//  iOS does not expose MAC addresses, so a device is identified by its
//  hostname when it has one, otherwise by its IP address. A device without a
//  hostname that gets a new IP from the router can therefore show up as new.
//

import Foundation
import NetworkExtension

struct KnownDevice: Codable {
    var identifier: String
    var lastIP: String
    var hostname: String?
    let firstSeen: Date
    var lastSeen: Date
}

struct KnownNetwork: Codable {
    var devices: [String: KnownDevice] = [:]
    var lastScan: Date?
}

@MainActor
final class KnownDevicesStore {
    static let shared = KnownDevicesStore()

    private var networks: [String: KnownNetwork] = [:]
    private let fileURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("known-devices.json")
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: KnownNetwork].self, from: data) {
            networks = stored
        }
    }

    /// Wi-Fi name when location access allows it, otherwise the subnet.
    static func networkKey(subnetBase: String) async -> String {
        if let ssid = await NEHotspotNetwork.fetchCurrent()?.ssid {
            return "ssid:\(ssid)"
        }
        return "subnet:\(subnetBase)"
    }

    static func identifier(for device: NetworkDevice) -> String {
        if let hostname = device.hostname, !hostname.isEmpty, hostname != device.ip {
            return "host:\(hostname.lowercased())"
        }
        return "ip:\(device.ip)"
    }

    func lastScan(on network: String) -> Date? {
        networks[network]?.lastScan
    }

    /// Saves a finished scan and returns the identifiers that had not been
    /// seen on this network before. The first scan of a network only builds
    /// the baseline, so it reports nothing as new.
    func recordScan(_ devices: [NetworkDevice], on network: String, at date: Date = Date()) -> (newIdentifiers: Set<String>, isFirstScan: Bool) {
        var known = networks[network] ?? KnownNetwork()
        let isFirstScan = known.lastScan == nil
        var newIdentifiers = Set<String>()

        for device in devices {
            let id = Self.identifier(for: device)
            // Names from mDNS come and go between scans, so a device is also
            // recognized by the address it had last time.
            let previousID = known.devices[id] != nil ? id : known.devices.first { $0.value.lastIP == device.ip }?.key
            if let previousID, var existing = known.devices.removeValue(forKey: previousID) {
                existing.identifier = id
                existing.lastIP = device.ip
                existing.hostname = device.hostname ?? existing.hostname
                existing.lastSeen = date
                known.devices[id] = existing
            } else {
                if !isFirstScan { newIdentifiers.insert(id) }
                known.devices[id] = KnownDevice(
                    identifier: id,
                    lastIP: device.ip,
                    hostname: device.hostname,
                    firstSeen: date,
                    lastSeen: date
                )
            }
        }

        known.lastScan = date
        networks[network] = known
        save()
        return (newIdentifiers, isFirstScan)
    }

    /// Forgets every device on a network; the next scan starts a new baseline.
    func reset(network: String) {
        networks[network] = nil
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(networks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
