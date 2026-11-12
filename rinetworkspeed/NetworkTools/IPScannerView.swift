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
            errorMessage = String(localized: "Could not determine local subnet.")
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

    private let accentBlue = Color(red: 0.24, green: 0.45, blue: 0.99)

    private let heroTint = Color(red: 0.12, green: 0.25, blue: 0.72)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                heroCard
                devicesList
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .appPageBackground()
        .navigationTitle("IP Scanner")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedDevice) { device in
            DeviceDetailSheet(device: device, vm: vm)
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Local Network")
                        .appFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundStyle(AppTheme.ink.opacity(0.75))
                        .textCase(.uppercase)
                    Text(vm.subnetBase.isEmpty ? "Not Connected" : "\(vm.subnetBase).1–254")
                        .appFont(size: 24, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.ink)
                    if !vm.localIP.isEmpty {
                        Text("Your IP: \(vm.localIP)")
                            .appFont(size: 13, weight: .medium, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.ink.opacity(0.75))
                    }
                }

                Spacer(minLength: 12)

                Image(systemName: "network")
                    .appFont(size: 30, weight: .semibold)
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 58, height: 58)
                    .background(AppTheme.ink.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Text("Discover devices on local network")
                .appFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.ink.opacity(0.75))

            if vm.isScanning || vm.scannedCount > 0 {
                progressSummary
            }

            if let errorMessage = vm.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .appFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.ink)
            }

            Button {
                vm.isScanning ? vm.stopScan() : vm.startScan()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: vm.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right")
                    Text(vm.isScanning ? "Stop" : "Scan")
                }
            }
            .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, tint: heroTint))
        }
        .appHeroCard(tint: heroTint)
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.isScanning ? "Scanning…" : "Scan Complete")
                .appFont(size: 11, weight: .semibold, design: .rounded)
                .foregroundStyle(AppTheme.ink.opacity(0.65))
                .textCase(.uppercase)

            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    ScannerHeroStat(value: "\(vm.discoveredDevices.count)", label: "Devices")
                    AppMetricDivider()
                    ScannerHeroStat(value: "\(vm.scannedCount)/254", label: "Scanned")
                    AppMetricDivider()
                    ScannerHeroStat(value: "\(Int(vm.progress * 100))%", label: "Progress")
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.ink.opacity(0.18))
                        Capsule()
                            .fill(AppTheme.ink)
                            .frame(width: geo.size.width * vm.progress)
                            .animation(.linear(duration: 0.2), value: vm.progress)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 14)
            }
            .padding(.vertical, 12)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Devices List

    @ViewBuilder
    private var devicesList: some View {
        if vm.discoveredDevices.isEmpty && !vm.isScanning && vm.scannedCount == 0 {
            AppEmptyState(
                icon: "network",
                title: "No Scan Yet",
                message: "Tap Scan to discover devices on your local network."
            )
            .appCard(padding: nil)
        } else if vm.discoveredDevices.isEmpty && !vm.isScanning {
            AppEmptyState(
                icon: "wifi.slash",
                title: "No Devices Found",
                message: "No responsive devices were found on \(vm.subnetBase).x"
            )
            .appCard(padding: nil)
        } else if vm.discoveredDevices.isEmpty {
            AppEmptyState(icon: "dot.radiowaves.left.and.right", title: "Scanning…")
                .appCard(padding: nil)
        } else {
            AppSection("\(vm.discoveredDevices.count) devices found") {
                ForEach(vm.discoveredDevices) { device in
                    Button {
                        selectedDevice = device
                    } label: {
                        DeviceRow(device: device)
                    }
                    .buttonStyle(AppRowButtonStyle())

                    if device.id != vm.discoveredDevices.last?.id {
                        AppRowDivider()
                    }
                }
            }
        }
    }
}

// MARK: - Hero Stat

/// Value + caption pair shown inside the hero summary strip.
private struct ScannerHeroStat: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .appFont(size: 17, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(AppTheme.ink)
                .contentTransition(.numericText())
            Text(label)
                .appFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Device Type Tint

private extension DeviceIconType {
    var tint: Color {
        switch self {
        case .router: Color(red: 0.24, green: 0.45, blue: 0.99)
        case .phone: AppTheme.accent
        case .laptop: Color(red: 0.20, green: 0.80, blue: 0.65)
        case .tv: AppTheme.upload
        case .printer: Color(red: 0.93, green: 0.30, blue: 0.60)
        case .unknown: Color(white: 0.45)
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let device: NetworkDevice

    var body: some View {
        HStack(spacing: 14) {
            AppIconTile(systemName: device.deviceType.rawValue, tint: device.deviceType.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.hostname ?? device.ip)
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                if device.hostname != nil {
                    Text(device.ip)
                        .appFont(size: 12, weight: .regular, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                AppPill(text: "\(Int(device.responseTime)) ms", tint: AppTheme.ping)
                    .monospacedDigit()
                Text(":\(device.openPort)")
                    .appFont(size: 11, weight: .medium, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            AppChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Device Detail Sheet

struct DeviceDetailSheet: View {
    let device: NetworkDevice
    let vm: IPScannerViewModel
    @State private var openPorts: [Int] = []
    @State private var isScanning = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    header

                    AppSection("Device Info") {
                        infoRow(label: "IP Address", value: device.ip)
                        AppRowDivider(leadingInset: 16)
                        if let hostname = device.hostname {
                            infoRow(label: "Hostname", value: hostname)
                            AppRowDivider(leadingInset: 16)
                        }
                        infoRow(label: "Device Type",
                                value: device.deviceType.rawValue.replacingOccurrences(of: ".fill", with: "").capitalized)
                        AppRowDivider(leadingInset: 16)
                        infoRow(label: "Response Time", value: "\(Int(device.responseTime)) ms")
                        AppRowDivider(leadingInset: 16)
                        infoRow(label: "First Open Port", value: "\(device.openPort) (\(serviceName(for: device.openPort)))")
                    }

                    AppSection("Open Ports") {
                        if isScanning {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(AppTheme.ink)
                                Text("Scanning common ports…")
                                    .appFont(size: 14, weight: .medium, design: .rounded)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        } else if openPorts.isEmpty {
                            Text("No additional open ports found")
                                .appFont(size: 14, weight: .medium, design: .rounded)
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        } else {
                            ForEach(openPorts, id: \.self) { port in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(AppTheme.ping)
                                        .frame(width: 8, height: 8)
                                    Text("\(port)")
                                        .appFont(size: 15, weight: .semibold, design: .rounded)
                                        .monospacedDigit()
                                        .foregroundStyle(AppTheme.primaryText)
                                    Spacer()
                                    AppPill(text: LocalizedStringKey(serviceName(for: port)), tint: AppTheme.ping)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                if port != openPorts.last {
                                    AppRowDivider(leadingInset: 34)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .appPageBackground()
            .navigationTitle(device.hostname ?? device.ip)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(AppTheme.background)
        .task {
            isScanning = true
            openPorts = await vm.probeCommonPorts(ip: device.ip)
            isScanning = false
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppIconTile(systemName: device.deviceType.rawValue, tint: device.deviceType.tint, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.hostname ?? device.ip)
                    .appFont(size: 18, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                if device.hostname != nil {
                    Text(device.ip)
                        .appFont(size: 13, weight: .medium, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Spacer(minLength: 8)

            AppPill(text: "\(Int(device.responseTime)) ms", tint: AppTheme.ping)
                .monospacedDigit()
        }
        .padding(.top, 8)
    }

    private func infoRow(label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .appFont(size: 15, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .appFont(size: 15, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
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
    .preferredColorScheme(.dark)
}
