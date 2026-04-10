//
//  PortScannerView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Network
import Combine

// MARK: - Models

struct PortResult: Identifiable {
    let id = UUID()
    let port: Int
    let isOpen: Bool
    let serviceName: String
    let responseTime: Double  // ms (0 if closed)
}

enum PortPreset: String, CaseIterable, Identifiable {
    case web      = "Web"
    case mail     = "Mail"
    case ftp      = "FTP"
    case ssh      = "SSH"
    case database = "Database"
    case common   = "Common"

    var id: String { rawValue }

    var ports: [Int] {
        switch self {
        case .web:      return [80, 443, 8080, 8443, 3000, 5000]
        case .mail:     return [25, 110, 143, 465, 587, 993, 995]
        case .ftp:      return [21, 990]
        case .ssh:      return [22, 2222]
        case .database: return [3306, 5432, 27017, 6379, 1433, 1521]
        case .common:   return [21, 22, 23, 25, 53, 80, 110, 143, 443,
                                445, 548, 587, 993, 995, 3306, 5432, 8080, 8443]
        }
    }

    var icon: String {
        switch self {
        case .web:      return "globe"
        case .mail:     return "envelope.fill"
        case .ftp:      return "folder.fill"
        case .ssh:      return "terminal.fill"
        case .database: return "cylinder.fill"
        case .common:   return "list.bullet"
        }
    }
}

// MARK: - Thread-safe Resume Box

private final class ResumableBox<T: Sendable>: @unchecked Sendable {
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

// MARK: - ViewModel

@MainActor
final class PortScannerViewModel: ObservableObject {
    @Published var targetHost: String = ""
    @Published var portRangeText: String = "1-1024"
    @Published var results: [PortResult] = []
    @Published var isScanning = false
    @Published var scannedCount = 0
    @Published var showOnlyOpen = false
    @Published var selectedPreset: PortPreset?
    @Published var errorMessage: String?

    private var scanTask: Task<Void, Never>?

    init(initialHost: String = "") {
        targetHost = initialHost
    }

    var openCount: Int { results.filter(\.isOpen).count }

    var filteredResults: [PortResult] {
        showOnlyOpen ? results.filter(\.isOpen) : results
    }

    func applyPreset(_ preset: PortPreset) {
        selectedPreset = preset
        portRangeText = preset.ports.map(String.init).joined(separator: ",")
    }

    func startScan() {
        let host = targetHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { errorMessage = "Enter a target host."; return }

        let ports = parsePorts()
        guard !ports.isEmpty else { errorMessage = "Enter a valid port range or select a preset."; return }

        isScanning = true
        results = []
        scannedCount = 0
        errorMessage = nil

        scanTask = Task {
            // Batches of 40 concurrent connections
            let batches = stride(from: 0, to: ports.count, by: 40).map {
                Array(ports[$0..<min($0 + 40, ports.count)])
            }
            for batch in batches {
                guard !Task.isCancelled else { break }
                await withTaskGroup(of: PortResult.self) { group in
                    for port in batch {
                        group.addTask { [weak self] in
                            guard let self else {
                                return PortResult(port: port, isOpen: false,
                                                  serviceName: "", responseTime: 0)
                            }
                            return await self.probePort(host: host, port: port)
                        }
                    }
                    for await result in group {
                        results.append(result)
                        results.sort { $0.port < $1.port }
                        scannedCount += 1
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

    // MARK: - Port Probe

    private func probePort(host: String, port: Int) async -> PortResult {
        let (isOpen, ms) = await tcpProbe(host: host, port: UInt16(port))
        return PortResult(port: port, isOpen: isOpen,
                          serviceName: Self.serviceName(for: port), responseTime: ms)
    }

    private func tcpProbe(host: String, port: UInt16) async -> (Bool, Double) {
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return (false, 0) }
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)

        return await withCheckedContinuation { cont in
            let box = ResumableBox<(Bool, Double)>(cont)
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
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                conn.cancel()
                box.resume(returning: (false, 0))
            }
        }
    }

    // MARK: - Helpers

    private func parsePorts() -> [Int] {
        var ports = Set<Int>()
        let parts = portRangeText.split(separator: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("-") {
                let bounds = trimmed.split(separator: "-")
                if bounds.count == 2,
                   let lo = Int(bounds[0].trimmingCharacters(in: .whitespaces)),
                   let hi = Int(bounds[1].trimmingCharacters(in: .whitespaces)),
                   lo > 0, hi <= 65535, lo <= hi {
                    (lo...min(hi, 65535)).forEach { ports.insert($0) }
                }
            } else if let p = Int(trimmed), p > 0, p <= 65535 {
                ports.insert(p)
            }
        }
        return ports.sorted()
    }

    static func serviceName(for port: Int) -> String {
        switch port {
        case 21:    return "FTP"
        case 22:    return "SSH"
        case 23:    return "Telnet"
        case 25:    return "SMTP"
        case 53:    return "DNS"
        case 80:    return "HTTP"
        case 110:   return "POP3"
        case 143:   return "IMAP"
        case 443:   return "HTTPS"
        case 445:   return "SMB"
        case 548:   return "AFP"
        case 587:   return "SMTP/TLS"
        case 993:   return "IMAPS"
        case 995:   return "POP3S"
        case 1433:  return "MSSQL"
        case 1521:  return "Oracle"
        case 2222:  return "SSH Alt"
        case 3000:  return "Dev-HTTP"
        case 3306:  return "MySQL"
        case 5000:  return "Dev-HTTP"
        case 5432:  return "PostgreSQL"
        case 6379:  return "Redis"
        case 8080:  return "HTTP Alt"
        case 8443:  return "HTTPS Alt"
        case 27017: return "MongoDB"
        default:    return ""
        }
    }
}

// MARK: - View

struct PortScannerView: View {
    @StateObject private var vm: PortScannerViewModel
    @FocusState private var hostFocused: Bool

    init(initialHost: String = "") {
        _vm = StateObject(wrappedValue: PortScannerViewModel(initialHost: initialHost))
    }

    private let bg     = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let accent = Color(red: 0.84, green: 0.28, blue: 0.74)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                configCard
                if vm.isScanning || !vm.results.isEmpty { statsRow }
                if !vm.results.isEmpty { resultsList }
                if let err = vm.errorMessage {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle.fill",
                                          description: Text(err))
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(bg.ignoresSafeArea())
        .navigationTitle("Port Scanner")
        .navigationBarTitleDisplayMode(.large)
        .onTapGesture { hostFocused = false }
    }

    // MARK: - Config Card

    private var configCard: some View {
        VStack(spacing: 14) {
            // Host input
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                TextField("Host or IP (e.g. 192.168.1.1)", text: $vm.targetHost)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .focused($hostFocused)
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Port range input
            HStack(spacing: 12) {
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                TextField("Ports: 80,443 or 1-1024", text: $vm.portRangeText)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PortPreset.allCases) { preset in
                        Button {
                            vm.applyPreset(preset)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: preset.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(preset.rawValue)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(vm.selectedPreset == preset ? accent : .white.opacity(0.50))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(vm.selectedPreset == preset
                                          ? accent.opacity(0.20)
                                          : Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(vm.selectedPreset == preset ? accent.opacity(0.55) : Color.clear,
                                            lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            // Scan / Stop
            Button {
                hostFocused = false
                vm.isScanning ? vm.stopScan() : vm.startScan()
            } label: {
                Text(vm.isScanning ? "Stop Scan" : "Start Scan")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(vm.isScanning
                                  ? LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing)
                                  : LinearGradient(colors: [accent, Color(red: 0.54, green: 0.12, blue: 0.48)],
                                                   startPoint: .leading, endPoint: .trailing))
                    )
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statBubble(value: "\(vm.openCount)", label: "Open", color: .green)
            statBubble(value: "\(vm.scannedCount - vm.openCount)", label: "Closed", color: .white.opacity(0.25))
            statBubble(value: "\(vm.scannedCount)", label: "Scanned", color: accent)

            Spacer()

            HStack(spacing: 6) {
                Text("Open only")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.50))
                Toggle("", isOn: $vm.showOnlyOpen)
                    .toggleStyle(SwitchToggleStyle(tint: accent))
                    .labelsHidden()
            }
        }
        .padding(.horizontal, 4)
    }

    private func statBubble(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.40))
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        VStack(spacing: 0) {
            if vm.filteredResults.isEmpty {
                Text(vm.showOnlyOpen ? "No open ports found" : "No results yet")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.40))
                    .padding(24)
            } else {
                ForEach(vm.filteredResults) { result in
                    PortRow(result: result)
                    if result.id != vm.filteredResults.last?.id {
                        Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Port Row

private struct PortRow: View {
    let result: PortResult

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(result.isOpen ? Color.green : Color.white.opacity(0.12))
                .frame(width: 10, height: 10)

            Text("\(result.port)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(result.isOpen ? .white : .white.opacity(0.40))
                .frame(width: 48, alignment: .leading)

            if !result.serviceName.isEmpty {
                Text(result.serviceName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(result.isOpen ? Color(red: 0.84, green: 0.28, blue: 0.74) : .white.opacity(0.20))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(result.isOpen
                                  ? Color(red: 0.84, green: 0.28, blue: 0.74).opacity(0.15)
                                  : Color.white.opacity(0.04))
                    )
            }

            Spacer()

            if result.isOpen {
                Text(String(format: "%.0f ms", result.responseTime))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.80))
            } else {
                Text("closed")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.20))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

#Preview {
    NavigationStack {
        PortScannerView()
    }
}
