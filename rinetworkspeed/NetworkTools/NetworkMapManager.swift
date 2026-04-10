//
//  NetworkMapManager.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Combine
import Network
import Darwin
import UIKit

// MARK: - MapDeviceType

enum MapDeviceType: String, CaseIterable {
    case router  = "wifi.router.fill"
    case phone   = "iphone"
    case laptop  = "laptopcomputer"
    case tablet  = "ipad"
    case tv      = "tv.fill"
    case iot     = "lightbulb.fill"
    case unknown = "desktopcomputer"

    var displayName: String {
        switch self {
        case .router:  return "Router / Gateway"
        case .phone:   return "Smartphone"
        case .laptop:  return "Laptop / Desktop"
        case .tablet:  return "Tablet"
        case .tv:      return "Smart TV / Media"
        case .iot:     return "IoT / Smart Device"
        case .unknown: return "Unknown Device"
        }
    }

    var nodeColor: Color {
        switch self {
        case .router:  return Color(red: 59/255,  green: 130/255, blue: 246/255)
        case .phone:   return Color(red: 168/255, green: 85/255,  blue: 247/255)
        case .laptop:  return Color(red: 52/255,  green: 211/255, blue: 153/255)
        case .tablet:  return Color(red: 234/255, green: 179/255, blue: 8/255)
        case .tv:      return Color(red: 249/255, green: 115/255, blue: 22/255)
        case .iot:     return Color(red: 239/255, green: 68/255,  blue: 68/255)
        case .unknown: return Color.white.opacity(0.50)
        }
    }
}

// MARK: - MapDevice

struct MapDevice: Identifiable, Equatable {
    let id: UUID
    var ip: String
    var hostname: String?
    var deviceType: MapDeviceType
    var macAddress: String?
    var responseTime: Double   // ms
    var isCurrentDevice: Bool

    init(
        id: UUID = UUID(),
        ip: String,
        hostname: String? = nil,
        deviceType: MapDeviceType = .unknown,
        macAddress: String? = nil,
        responseTime: Double = 0,
        isCurrentDevice: Bool = false
    ) {
        self.id = id
        self.ip = ip
        self.hostname = hostname
        self.deviceType = deviceType
        self.macAddress = macAddress
        self.responseTime = responseTime
        self.isCurrentDevice = isCurrentDevice
    }

    static func == (lhs: MapDevice, rhs: MapDevice) -> Bool { lhs.id == rhs.id }
}

// MARK: - NetworkMapManager

@MainActor
final class NetworkMapManager: ObservableObject {
    @Published var devices: [MapDevice] = []
    @Published var isScanning: Bool = false
    @Published var lastScanDate: Date?
    @Published var scannedCount: Int = 0
    @Published var progress: Double = 0

    private(set) var localIP: String = ""
    private(set) var subnetBase: String = ""
    private(set) var routerIP: String = ""

    private var scanTask: Task<Void, Never>?

    // OUI prefix → device type  (6 hex chars, uppercase, no separators)
    private static let ouiTable: [String: MapDeviceType] = [
        // Apple phones
        "F81EDF": .phone, "DCA904": .phone, "F4F15A": .phone, "3C2EFF": .phone,
        "E849C0": .phone, "A8968A": .phone,
        // Apple tablets
        "A85E45": .tablet, "F0B479": .tablet, "2C1AA6": .tablet,
        // Apple laptops / Macs
        "A483E7": .laptop, "8C8590": .laptop, "A45E60": .laptop, "3C15C2": .laptop,
        "F0DBF8": .laptop,
        // Samsung phones
        "7445CE": .phone, "78BDBC": .phone, "ACBC32": .phone, "9854A4": .phone,
        // Huawei
        "AC4CA5": .phone, "8C34FD": .phone,
        // Xiaomi
        "000EC6": .phone, "7851CE": .phone,
        // Routers: ASUS, TP-Link, Netgear, FritzBox, AVM, D-Link, Linksys
        "50465D": .router, "14EBB6": .router, "C8D7B3": .router,
        "00904C": .router, "E8DE27": .router, "189C5D": .router,
        "1C5F2B": .router, "C0A0BB": .router, "D8EB97": .router,
        "00265A": .router, "204E7F": .router,
        // Smart TVs: Samsung, LG, Sony, TCL
        "A823FE": .tv, "CC6DAD": .tv, "8C79F0": .tv,
        "BC5FF4": .tv, "E06078": .tv, "78BD5A": .tv,
        // IoT / Smart Home: Philips Hue, IKEA, Amazon Echo, Google Nest
        "B4E62D": .iot, "18FE34": .iot, "44650D": .iot,
        "F0272D": .iot, "687180": .iot, "509A4C": .iot,
    ]

    init() {
        let ip = Self.getLocalIPAddress() ?? ""
        localIP = ip
        subnetBase = Self.subnetBase(for: ip)
        routerIP = subnetBase.isEmpty ? "" : "\(subnetBase).1"
    }

    // MARK: - Public scan()

    func scan() async {
        guard !isScanning else { return }
        scanTask?.cancel()

        isScanning = true
        devices = []
        scannedCount = 0
        progress = 0
        lastScanDate = nil

        guard !subnetBase.isEmpty else { isScanning = false; return }

        let base = subnetBase
        let currentIP = localIP

        // Add this device immediately
        let selfDevice = MapDevice(
            ip: currentIP,
            hostname: UIDevice.current.name,
            deviceType: .phone,
            macAddress: nil,
            responseTime: 0,
            isCurrentDevice: true
        )
        devices.append(selfDevice)

        // Probe gateway/router first
        let gw = "\(base).1"
        if gw != currentIP, let router = await probeHost(ip: gw, forceRouter: true) {
            devices.append(router)
            sortDevices()
        }

        // Scan the rest of the subnet in batches of 50
        let allIPs = (2...254).map { "\(base).\($0)" }
        let toScan = allIPs.filter { $0 != currentIP && $0 != gw }
        let total = Double(toScan.count)

        let batches = stride(from: 0, to: toScan.count, by: 50).map {
            Array(toScan[$0..<min($0 + 50, toScan.count)])
        }

        scanTask = Task {
            for batch in batches {
                guard !Task.isCancelled else { break }
                await withTaskGroup(of: MapDevice?.self) { group in
                    for ip in batch {
                        group.addTask { [weak self] in
                            guard let self else { return nil }
                            return await self.probeHost(ip: ip, forceRouter: false)
                        }
                    }
                    for await result in group {
                        scannedCount += 1
                        progress = Double(scannedCount) / total
                        if let device = result {
                            devices.append(device)
                            sortDevices()
                        }
                    }
                }
            }
            isScanning = false
            lastScanDate = Date()
        }
        await scanTask?.value
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    // MARK: - Private probe

    private func probeHost(ip: String, forceRouter: Bool) async -> MapDevice? {
        let ports: [UInt16] = [80, 443, 22, 8080, 62078, 548, 9100, 53]
        for port in ports {
            guard !Task.isCancelled else { return nil }
            let (connected, ms) = await tcpProbe(ip: ip, port: port)
            if connected {
                let hostname = await Self.reverseDNS(ip)
                let dtype: MapDeviceType = forceRouter
                    ? .router
                    : Self.guessDeviceType(port: Int(port), hostname: hostname, mac: nil)
                return MapDevice(
                    ip: ip,
                    hostname: hostname,
                    deviceType: dtype,
                    macAddress: nil,
                    responseTime: ms,
                    isCurrentDevice: false
                )
            }
        }
        return nil
    }

    private func tcpProbe(ip: String, port: UInt16) async -> (Bool, Double) {
        let host = NWEndpoint.Host(ip)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return (false, 0) }
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = []
        let conn = NWConnection(host: host, port: nwPort, using: params)

        return await withCheckedContinuation { continuation in
            let box = MapResumeBox<(Bool, Double)>(continuation)
            let start = Date()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ms = Date().timeIntervalSince(start) * 1000
                    conn.cancel()
                    box.resume(returning: (true, ms))
                case .failed, .cancelled:
                    box.resume(returning: (false, 0))
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                conn.cancel()
                box.resume(returning: (false, 0))
            }
        }
    }

    // MARK: - Helpers

    static func guessDeviceType(port: Int, hostname: String?, mac: String?) -> MapDeviceType {
        // 1. OUI prefix
        if let mac = mac {
            let clean = mac
                .components(separatedBy: CharacterSet(charactersIn: ":-"))
                .joined()
                .uppercased()
            if clean.count >= 6, let t = ouiTable[String(clean.prefix(6))] { return t }
        }
        // 2. Hostname keywords
        let name = (hostname ?? "").lowercased()
        if name.contains("router") || name.contains("gateway") || name.contains("fritz")
            || name.contains("modem") || name.contains("ap-") || name.contains("access-point") { return .router }
        if name.contains("ipad") || name.contains("tablet") { return .tablet }
        if name.contains("iphone") || name.contains("android") || name.contains("pixel") { return .phone }
        if name.contains("macbook") || name.contains("laptop")
            || name.contains("desktop") || name.contains("pc-") { return .laptop }
        if name.contains("-tv") || name.contains("appletv") || name.contains("chromecast")
            || name.contains("roku") || name.contains("smarttv") { return .tv }
        if name.contains("printer") || name.contains("camera") || name.contains("hue")
            || name.contains("nest") || name.contains("ring") { return .iot }
        // 3. Port hints
        switch port {
        case 62078: return .phone
        case 22:    return .laptop
        case 9100:  return .iot
        case 53:    return .router
        case 80, 443: return .router
        default:    return .unknown
        }
    }

    static func reverseDNS(_ ip: String) async -> String? {
        await Task.detached(priority: .utility) {
            var sa = sockaddr_in()
            sa.sin_family = sa_family_t(AF_INET)
            guard inet_pton(AF_INET, ip, &sa.sin_addr) == 1 else { return nil }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let res = withUnsafePointer(to: &sa) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size),
                                &buf, socklen_t(buf.count), nil, 0, NI_NAMEREQD)
                }
            }
            guard res == 0 else { return nil }
            let s = String(cString: buf)
            return s.isEmpty ? nil : s
        }.value
    }

    private static func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: current.pointee.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(current.pointee.ifa_addr, socklen_t(MemoryLayout<sockaddr_in>.size),
                        &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST)
            return String(cString: buf)
        }
        return nil
    }

    private static func subnetBase(for ip: String) -> String {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return "" }
        return "\(parts[0]).\(parts[1]).\(parts[2])"
    }

    private func sortDevices() {
        devices.sort { Self.ipInt($0.ip) < Self.ipInt($1.ip) }
    }

    static func ipInt(_ ip: String) -> Int {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return 0 }
        return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]
    }
}

// MARK: - Thread-safe continuation box

private final class MapResumeBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Never>?

    init(_ cont: CheckedContinuation<T, Never>) { self.cont = cont }

    func resume(returning value: T) {
        lock.lock(); defer { lock.unlock() }
        guard let c = cont else { return }
        cont = nil
        c.resume(returning: value)
    }
}
