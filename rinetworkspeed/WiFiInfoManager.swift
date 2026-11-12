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
import NetworkExtension
import Darwin
import UIKit

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
    /// Security of the joined network (for example "WPA2 Personal").
    /// iOS does not expose RSSI or the frequency band to regular apps, so
    /// those values are intentionally not shown rather than guessed.
    @Published var securityType: String?
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

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // Permission is requested only when the user opens the Wi-Fi details
        // (see `requestLocationIfNeeded()`), never as a side effect of a refresh.
        authorizationStatus = locationManager.authorizationStatus

        updateLocalNetworkDetails()

        guard hasLocationPermission else {
            ssid = nil
            bssid = nil
            securityType = nil
            externalIP = nil
            ispName = nil
            natType = inferNATType(localIP: ipAddress, externalIP: nil)
            return
        }

        await updateCurrentWiFiNetwork()

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

    var canRequestLocation: Bool {
        authorizationStatus == .notDetermined
    }

    var hasLocationPermission: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    private func updateCurrentWiFiNetwork() async {
        // Requires the "Access WiFi Information" entitlement and location permission.
        guard let network = await NEHotspotNetwork.fetchCurrent() else {
            ssid = nil
            bssid = nil
            securityType = nil
            return
        }

        ssid = network.ssid
        bssid = network.bssid
        securityType = Self.describe(network.securityType)
    }

    private static func describe(_ type: NEHotspotNetworkSecurityType) -> String? {
        switch type {
        case .open: return String(localized: "Open")
        case .WEP: return "WEP"
        case .personal: return String(localized: "WPA/WPA2/WPA3 Personal")
        case .enterprise: return String(localized: "WPA/WPA2/WPA3 Enterprise")
        case .unknown: return nil
        @unknown default: return nil
        }
    }

    private func updateLocalNetworkDetails() {
        let details = localInterfaceDetails()
        ipAddress = details.ipAddress
        subnetMask = details.subnetMask
        routerIP = details.routerIP
        dnsServers = currentDNSServers()
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

    // The two lookups below are the only requests that send data to third
    // parties (ipify.org and ipapi.co). They reveal the public IP address and
    // are disclosed in the README and PrivacyInfo.xcprivacy.
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
            return String(localized: "Carrier NAT")
        }

        if let externalIP, externalIP == localIP {
            return String(localized: "Open NAT")
        }

        if isPrivateIPv4(localIP) {
            return String(localized: "Moderate NAT")
        }

        return String(localized: "Unknown")
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
