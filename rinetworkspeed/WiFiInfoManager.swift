//
//  WiFiInfoManager.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Combine
import CoreLocation
import Foundation
import SystemConfiguration.CaptiveNetwork
import Darwin
import UIKit

enum SignalStrength {
    case excellent
    case good
    case fair
    case poor

    var title: String {
        switch self {
        case .excellent:
            return "Mukemmel"
        case .good:
            return "Good"
        case .fair:
            return "Fair"
        case .poor:
            return "Zayif"
        }
    }

    var color: Color {
        switch self {
        case .excellent:
            return .green
        case .good:
            return .yellow
        case .fair:
            return .orange
        case .poor:
            return .red
        }
    }
}

private struct IPifyResponse: Decodable {
    let ip: String
}

private struct IPApiResponse: Decodable {
    let ip: String?
    let org: String?
    let asn: String?
}

@MainActor
final class WiFiInfoManager: NSObject, ObservableObject {
    @Published var ssid: String?
    @Published var bssid: String?
    @Published var rssi: Int = -80
    @Published var signalStrength: SignalStrength = .poor
    @Published var frequencyBand: String = "5 GHz"
    @Published var ipAddress: String?
    @Published var subnetMask: String?
    @Published var routerIP: String?
    @Published var dnsServers: [String] = []
    @Published var externalIP: String?
    @Published var ispName: String?
    @Published var natType: String?
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var isRefreshing: Bool = false

    private let locationManager = CLLocationManager()
    private let sharedDefaults = UserDefaults(suiteName: "group.rinetworkspeedapp")

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        authorizationStatus = locationManager.authorizationStatus
        requestLocationIfNeeded()

        updateLocalNetworkDetails()

        guard hasLocationPermission else {
            ssid = nil
            bssid = nil
            externalIP = nil
            ispName = nil
            natType = inferNATType(localIP: ipAddress, externalIP: nil)
            return
        }

        updateCurrentWiFiNetwork()

        async let externalIPRequest = fetchExternalIP()
        async let ispRequest = fetchISPInfo()

        let fetchedExternalIP = await externalIPRequest
        externalIP = fetchedExternalIP

        if let ispResponse = await ispRequest {
            externalIP = fetchedExternalIP ?? ispResponse.ip
            ispName = ispResponse.org ?? ispResponse.asn
        } else {
            ispName = nil
        }

        natType = inferNATType(localIP: ipAddress, externalIP: externalIP)
    }

    func requestLocationIfNeeded() {
        let status = locationManager.authorizationStatus
        authorizationStatus = status

        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    var hasLocationPermission: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    private func updateCurrentWiFiNetwork() {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else {
            ssid = nil
            bssid = nil
            return
        }

        for interface in interfaces {
            guard let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any] else {
                continue
            }

            ssid = info[kCNNetworkInfoKeySSID as String] as? String
            bssid = info[kCNNetworkInfoKeyBSSID as String] as? String
            break
        }
    }

    private func updateLocalNetworkDetails() {
        let details = localInterfaceDetails()
        ipAddress = details.ipAddress
        subnetMask = details.subnetMask
        routerIP = details.routerIP
        dnsServers = currentDNSServers()

        let estimatedThroughput = max(
            sharedDefaults?.double(forKey: "downloadSpeed") ?? 0,
            sharedDefaults?.double(forKey: "uploadSpeed") ?? 0
        ) / 1_048_576

        rssi = estimatedRSSI(ipAddress: details.ipAddress, bandwidthMBps: estimatedThroughput)
        signalStrength = signalStrength(for: rssi)
        frequencyBand = estimatedFrequencyBand(rssi: rssi, bandwidthMBps: estimatedThroughput)
    }

    private func localInterfaceDetails() -> (ipAddress: String?, subnetMask: String?, routerIP: String?) {
        var address: String?
        var mask: String?
        var addrs: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else {
            return (nil, nil, nil)
        }

        defer {
            freeifaddrs(firstAddr)
        }

        var pointer = firstAddr
        while true {
            let interface = pointer.pointee

            if
                let name = interface.ifa_name,
                String(cString: name) == "en0",
                let addr = interface.ifa_addr,
                addr.pointee.sa_family == UInt8(AF_INET)
            {
                address = ipv4String(from: addr)
                if let netmask = interface.ifa_netmask {
                    mask = ipv4String(from: netmask)
                }
                break
            }

            guard let next = interface.ifa_next else { break }
            pointer = next
        }

        let router = inferredRouterIP(ipAddress: address, subnetMask: mask)
        return (address, mask, router)
    }

    private func ipv4String(from socketAddress: UnsafePointer<sockaddr>) -> String? {
        var hostName = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            socketAddress,
            socklen_t(socketAddress.pointee.sa_len),
            &hostName,
            socklen_t(hostName.count),
            nil,
            0,
            NI_NUMERICHOST
        )

        guard result == 0 else { return nil }
        return String(cString: hostName)
    }

    private func inferredRouterIP(ipAddress: String?, subnetMask: String?) -> String? {
        guard
            let ipAddress,
            let subnetMask,
            let ip = ipv4ToUInt32(ipAddress),
            let mask = ipv4ToUInt32(subnetMask)
        else {
            return nil
        }

        let network = ip & mask
        return uint32ToIPv4(network + 1)
    }

    private func ipv4ToUInt32(_ address: String) -> UInt32? {
        let octets = address.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return nil }

        return octets.enumerated().reduce(0) { partial, pair in
            partial | (UInt32(pair.element) << UInt32((3 - pair.offset) * 8))
        }
    }

    private func uint32ToIPv4(_ value: UInt32) -> String {
        [
            String((value >> 24) & 0xFF),
            String((value >> 16) & 0xFF),
            String((value >> 8) & 0xFF),
            String(value & 0xFF)
        ].joined(separator: ".")
    }

    private func estimatedRSSI(ipAddress: String?, bandwidthMBps: Double) -> Int {
        if bandwidthMBps >= 120 {
            return -45
        } else if bandwidthMBps >= 70 {
            return -56
        } else if bandwidthMBps >= 30 {
            return -67
        } else if ipAddress != nil {
            return -76
        }
        return -82
    }

    private func signalStrength(for rssi: Int) -> SignalStrength {
        switch rssi {
        case -55...0:
            return .excellent
        case -67 ... -56:
            return .good
        case -75 ... -68:
            return .fair
        default:
            return .poor
        }
    }

    private func estimatedFrequencyBand(rssi: Int, bandwidthMBps: Double) -> String {
        if bandwidthMBps >= 120 || rssi >= -58 {
            return "6 GHz"
        } else if bandwidthMBps >= 45 || rssi >= -70 {
            return "5 GHz"
        }
        return "2.4 GHz"
    }

    private func currentDNSServers() -> [String] {
        guard let contents = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) else {
            return []
        }

        return contents
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("nameserver ") else { return nil }
                return trimmed.replacingOccurrences(of: "nameserver ", with: "")
            }
    }

    private func fetchExternalIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org?format=json") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(IPifyResponse.self, from: data).ip
        } catch {
            return nil
        }
    }

    private func fetchISPInfo() async -> IPApiResponse? {
        guard let url = URL(string: "https://ipapi.co/json/") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(IPApiResponse.self, from: data)
        } catch {
            return nil
        }
    }

    private func inferNATType(localIP: String?, externalIP: String?) -> String? {
        guard let localIP else { return nil }

        if isCarrierGradeNAT(localIP) {
            return "Carrier NAT"
        }

        if let externalIP, externalIP == localIP {
            return "Open NAT"
        }

        if isPrivateIPv4(localIP) {
            return "Moderate NAT"
        }

        return "Unknown"
    }

    private func isPrivateIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }

        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }

    private func isCarrierGradeNAT(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }
}

extension WiFiInfoManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.authorizationStatus = manager.authorizationStatus
            if self?.hasLocationPermission == true {
                await self?.refresh()
            }
        }
    }
}
