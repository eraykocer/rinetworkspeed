//
//  IPScannerView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Network
import Darwin
import Combine

// MARK: - Models

enum DeviceIconType: String {
    case router   = "wifi.router.fill"
    case phone    = "iphone"
    case laptop   = "laptopcomputer"
    case tv       = "tv.fill"
    case printer  = "printer.fill"
    case unknown  = "desktopcomputer"
}

struct NetworkDevice: Identifiable {
    let id = UUID()
    var ip: String
    var hostname: String?
    var responseTime: Double   // ms
    var openPort: Int
    var deviceType: DeviceIconType
}

// MARK: - Resume Box (thread-safe continuation)

private final class ResumableBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Never>?

    init(_ cont: CheckedContinuation<T, Never>) { self.cont = cont }

    func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        guard let c = cont else { return }
        cont = nil
        c.resume(returning: value)
    }
}

// MARK: - ViewModel

@MainActor
final class IPScannerViewModel: ObservableObject {
    @Published var discoveredDevices: [NetworkDevice] = []
    @Published var isScanning = false
    @Published var scannedCount = 0
    @Published var progress: Double = 0
    @Published var localIP: String = ""
    @Published var subnetBase: String = ""
    @Published var errorMessage: String?

    private var scanTask: Task<Void, Never>?

    init() {
        let currentLocalIP = Self.getLocalIPAddress() ?? ""
        localIP = currentLocalIP
        subnetBase = Self.subnetBase(for: currentLocalIP)
    }

    private func updateSubnet() {
        subnetBase = Self.subnetBase(for: localIP)
    }

    func startScan() {
        guard !subnetBase.isEmpty else {
            errorMessage = "Could not determine local subnet."
            return
        }
        isScanning = true
        discoveredDevices = []
        scannedCount = 0
        progress = 0
        errorMessage = nil

        scanTask = Task {
            let base = subnetBase
            // Scan in batches of 50 for controlled concurrency
            let batches = stride(from: 1, through: 254, by: 50).map { start in
                (start...min(start + 49, 254)).map { "\(base).\($0)" }
            }

            for batch in batches {
                guard !Task.isCancelled else { break }
                await withTaskGroup(of: NetworkDevice?.self) { group in
                    for ip in batch {
                        group.addTask { [weak self] in
                            guard let self else { return nil }
                            return await self.probeHost(ip: ip)
                        }
                    }
                    for await result in group {
                        scannedCount += 1
                        progress = Double(scannedCount) / 254.0
                        if let device = result {
                            discoveredDevices.append(device)
                            discoveredDevices.sort { Self.ipToInt($0.ip) < Self.ipToInt($1.ip) }
                        }
                    }
                }
            }
            isScanning = false
        }
    }

    func stopScan() {
        scanTask?.cancel()
        isScanning = false
    }

    // MARK: - Probing

    private func probeHost(ip: String) async -> NetworkDevice? {
        let ports: [UInt16] = [80, 443, 22, 8080, 62078, 548, 9100]
        for port in ports {
            guard !Task.isCancelled else { return nil }
            let (connected, time) = await tcpProbe(ip: ip, port: port)
            if connected {
                let hostname = await Self.reverseDNS(ip)
                let dtype = Self.guessDeviceType(port: Int(port), hostname: hostname)
                return NetworkDevice(ip: ip, hostname: hostname,
                                     responseTime: time, openPort: Int(port),
                                     deviceType: dtype)
            }
        }
        return nil
    }

    func probeCommonPorts(ip: String) async -> [Int] {
        let common = [21, 22, 23, 25, 53, 80, 110, 143, 443, 445, 548,
                      587, 993, 995, 3306, 5432, 8080, 8443, 9100, 62078]
        var open: [Int] = []
        for port in common {
            let (connected, _) = await tcpProbe(ip: ip, port: UInt16(port))
            if connected { open.append(port) }
        }
        return open
    }

    private func tcpProbe(ip: String, port: UInt16) async -> (Bool, Double) {
        let host = NWEndpoint.Host(ip)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return (false, 0) }
        let params = NWParameters.tcp
        let conn = NWConnection(host: host, port: nwPort, using: params)

        return await withCheckedContinuation { continuation in
            let box = ResumableBox<(Bool, Double)>(continuation)
            let start = Date()

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ms = Date().timeIntervalSince(start) * 1000
                    conn.cancel()
                    box.resume(returning: (true, ms))
                case .failed, .cancelled:
                    box.resume(returning: (false, 0))
                default: break
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

    private static func guessDeviceType(port: Int, hostname: String?) -> DeviceIconType {
        let name = (hostname ?? "").lowercased()
        if name.contains("router") || name.contains("gateway") || name.contains("fritzbox") { return .router }
        if name.contains("iphone") || name.contains("ipad") || port == 62078 { return .phone }
        if name.contains("macbook") || name.contains("mac") || name.contains("laptop") || port == 22 { return .laptop }
        if name.contains("-tv") || name.contains("chromecast") || name.contains("roku") || name.contains("appletv") { return .tv }
        if name.contains("printer") || port == 9100 { return .printer }
        if port == 80 || port == 443 { return .router }
        return .unknown
    }

    static func reverseDNS(_ ipString: String) async -> String? {
        await Task.detached(priority: .utility) {
            var sa = sockaddr_in()
            sa.sin_family = sa_family_t(AF_INET)
            guard inet_pton(AF_INET, ipString, &sa.sin_addr) == 1 else { return nil }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = withUnsafePointer(to: &sa) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size),
                                &buf, socklen_t(buf.count), nil, 0, NI_NAMEREQD)
                }
            }
            guard result == 0 else { return nil }
            let s = String(cString: buf)
            return s.isEmpty ? nil : s
        }.value
    }

    private static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            let iface = ptr!.pointee
            if iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: iface.ifa_name)
                if name == "en0" || name == "en1" {
                    var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(iface.ifa_addr, socklen_t(MemoryLayout<sockaddr_in>.size),
                                &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: buf)
                }
            }
        }
        return address
    }

    private static func subnetBase(for ipAddress: String) -> String {
        let parts = ipAddress.split(separator: ".")
        guard parts.count == 4 else { return "" }
        return "\(parts[0]).\(parts[1]).\(parts[2])"
    }

    private static func ipToInt(_ ip: String) -> Int {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return 0 }
        return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]
    }
}

// MARK: - Views

struct IPScannerView: View {
    @StateObject private var vm = IPScannerViewModel()
    @State private var selectedDevice: NetworkDevice?

    private let bg = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let accentBlue = Color(red: 0.24, green: 0.45, blue: 0.99)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                subnetCard
                progressCard
                devicesList
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(bg.ignoresSafeArea())
        .navigationTitle("IP Scanner")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedDevice) { device in
            DeviceDetailSheet(device: device, vm: vm)
        }
    }

    // MARK: - Subnet Card
    private var subnetCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "network")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(accentBlue)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("Local Network")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Text(vm.subnetBase.isEmpty ? "Not Connected" : "\(vm.subnetBase).1–254")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if !vm.localIP.isEmpty {
                    Text("Your IP: \(vm.localIP)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Spacer()

            Button {
                vm.isScanning ? vm.stopScan() : vm.startScan()
            } label: {
                Text(vm.isScanning ? "Stop" : "Scan")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(
                            vm.isScanning
                                ? LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [accentBlue, Color(red: 0.12, green: 0.25, blue: 0.72)],
                                                 startPoint: .leading, endPoint: .trailing)
                        )
                    )
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Progress Card
    @ViewBuilder
    private var progressCard: some View {
        if vm.isScanning || vm.scannedCount > 0 {
            VStack(spacing: 10) {
                HStack {
                    Text(vm.isScanning ? "Scanning…" : "Scan Complete")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(vm.scannedCount) / 254")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(colors: [accentBlue, .cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * vm.progress, height: 6)
                            .animation(.linear(duration: 0.2), value: vm.progress)
                    }
                }
                .frame(height: 6)

                if !vm.discoveredDevices.isEmpty {
                    Text("\(vm.discoveredDevices.count) device\(vm.discoveredDevices.count == 1 ? "" : "s") found")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(accentBlue)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Devices List
    @ViewBuilder
    private var devicesList: some View {
        if vm.discoveredDevices.isEmpty && !vm.isScanning && vm.scannedCount == 0 {
            ContentUnavailableView(
                "No Scan Yet",
                systemImage: "network",
                description: Text("Tap Scan to discover devices on your local network.")
            )
            .foregroundStyle(.white)
            .padding(.top, 40)
        } else if vm.discoveredDevices.isEmpty && !vm.isScanning {
            ContentUnavailableView(
                "No Devices Found",
                systemImage: "wifi.slash",
                description: Text("No responsive devices were found on \(vm.subnetBase).x")
            )
            .foregroundStyle(.white)
            .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(vm.discoveredDevices) { device in
                    Button {
                        selectedDevice = device
                    } label: {
                        DeviceRow(device: device)
                    }
                    .buttonStyle(.plain)

                    if device.id != vm.discoveredDevices.last?.id {
                        Divider().background(Color.white.opacity(0.08)).padding(.leading, 68)
                    }
                }
            }
            .background(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let device: NetworkDevice

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.deviceType.rawValue)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color(red: 0.24, green: 0.45, blue: 0.99))
                .frame(width: 42, height: 42)
                .background(Color(red: 0.24, green: 0.45, blue: 0.99).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(device.hostname ?? device.ip)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if device.hostname != nil {
                    Text(device.ip)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(device.responseTime)) ms")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green)
                Text(":\(device.openPort)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Device Detail Sheet

struct DeviceDetailSheet: View {
    let device: NetworkDevice
    let vm: IPScannerViewModel
    @State private var openPorts: [Int] = []
    @State private var isScanning = false
    @Environment(\.dismiss) private var dismiss

    private let bg = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)

    var body: some View {
        NavigationStack {
            List {
                Section("Device Info") {
                    infoRow(label: "IP Address", value: device.ip)
                    if let hostname = device.hostname {
                        infoRow(label: "Hostname", value: hostname)
                    }
                    infoRow(label: "Device Type",
                            value: device.deviceType.rawValue.replacingOccurrences(of: ".fill", with: "").capitalized)
                    infoRow(label: "Response Time", value: "\(Int(device.responseTime)) ms")
                    infoRow(label: "First Open Port", value: "\(device.openPort) (\(serviceName(for: device.openPort)))")
                }

                Section {
                    if isScanning {
                        HStack {
                            ProgressView()
                            Text("Scanning common ports…")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        }
                    } else if openPorts.isEmpty {
                        Text("No additional open ports found")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(openPorts, id: \.self) { port in
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("\(port)")
                                    .font(.system(size: 14, design: .monospaced))
                                Spacer()
                                Text(serviceName(for: port))
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Open Ports")
                }
            }
            .navigationTitle(device.hostname ?? device.ip)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            isScanning = true
            openPorts = await vm.probeCommonPorts(ip: device.ip)
            isScanning = false
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private func serviceName(for port: Int) -> String {
        switch port {
        case 21: return "FTP"
        case 22: return "SSH"
        case 23: return "Telnet"
        case 25: return "SMTP"
        case 53: return "DNS"
        case 80: return "HTTP"
        case 110: return "POP3"
        case 143: return "IMAP"
        case 443: return "HTTPS"
        case 445: return "SMB"
        case 548: return "AFP"
        case 587: return "SMTP (TLS)"
        case 993: return "IMAPS"
        case 995: return "POP3S"
        case 3306: return "MySQL"
        case 5432: return "PostgreSQL"
        case 8080: return "HTTP Alt"
        case 8443: return "HTTPS Alt"
        case 9100: return "Printer"
        case 62078: return "iOS Lockdown"
        default: return "Unknown"
        }
    }
}

#Preview {
    NavigationStack {
        IPScannerView()
    }
}
