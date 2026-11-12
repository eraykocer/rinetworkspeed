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
        guard !host.isEmpty else { errorMessage = String(localized: "Enter a target host."); return }

        let ports = parsePorts()
        guard !ports.isEmpty else { errorMessage = String(localized: "Enter a valid port range or select a preset."); return }

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

    private let accent     = Color(red: 0.84, green: 0.28, blue: 0.74)
    private let accentDeep = Color(red: 0.54, green: 0.12, blue: 0.48)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                heroCard

                if let err = vm.errorMessage {
                    ToolErrorCard(title: "Error", message: err)
                }

                if vm.isScanning || !vm.results.isEmpty { summarySection }

                if !vm.results.isEmpty {
                    resultsSection
                } else if !vm.isScanning && vm.errorMessage == nil {
                    AppEmptyState(
                        icon: "door.left.hand.open",
                        title: "No Scan Yet",
                        message: "Enter a host, choose ports or a preset, then start the scan."
                    )
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .appPageBackground()
        .navigationTitle("Port Scanner")
        .toolReport(vm) { $0.reportText }
        .navigationBarTitleDisplayMode(.large)
        .onTapGesture { hostFocused = false }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ToolHeroHeader(
                icon: "door.left.hand.open",
                title: "Check open TCP ports on a host",
                subtitle: "Scan a port range or pick a preset to find listening services."
            )

            VStack(spacing: 10) {
                AppInputField(icon: "server.rack", placeholder: "Host or IP (e.g. 192.168.1.1)", text: $vm.targetHost, showsFavorites: true)
                    .focused($hostFocused)
                    .heroInset()

                AppInputField(icon: "number", placeholder: "Ports: 80,443 or 1-1024",
                              text: $vm.portRangeText, keyboard: .numbersAndPunctuation)
                    .heroInset()
            }

            // Presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PortPreset.allCases) { preset in
                        Button {
                            vm.applyPreset(preset)
                        } label: {
                            HeroChip(title: preset.rawValue, icon: preset.icon,
                                     isSelected: vm.selectedPreset == preset, selectedTint: accentDeep)
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
                HStack(spacing: 8) {
                    if vm.isScanning {
                        ProgressView().tint(accentDeep)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(vm.isScanning ? "Stop Scan" : "Start Scan")
                }
            }
            .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, tint: accentDeep))
        }
        .appHeroCard(tint: accentDeep)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        AppSection("Summary") {
            HStack(spacing: 0) {
                statCell(value: vm.openCount, label: "Open", color: AppTheme.ping)
                AppMetricDivider()
                statCell(value: vm.scannedCount - vm.openCount, label: "Closed", color: AppTheme.secondaryText)
                AppMetricDivider()
                statCell(value: vm.scannedCount, label: "Scanned", color: accent)
            }
            .padding(.vertical, 16)

            AppRowDivider(leadingInset: 16)

            AppRow(icon: "line.3.horizontal.decrease", tint: accent, title: "Open only") {
                Toggle("Open only", isOn: $vm.showOnlyOpen)
                    .labelsHidden()
                    .tint(accent)
            }
        }
    }

    private func statCell(value: Int, label: LocalizedStringKey, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: "\(value)")
                .appFont(size: 22, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .appFont(size: 11, weight: .semibold, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        AppSection("Results") {
            let results = vm.filteredResults
            if results.isEmpty {
                AppEmptyState(
                    icon: vm.showOnlyOpen ? "door.left.hand.closed" : "hourglass",
                    title: vm.showOnlyOpen ? "No open ports found" : "No results yet"
                )
            } else {
                ForEach(results) { result in
                    PortRow(result: result, accent: accent)
                    if result.id != results.last?.id {
                        AppRowDivider(leadingInset: 16)
                    }
                }
            }
        }
    }
}

// MARK: - Port Row

private struct PortRow: View {
    let result: PortResult
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: String(result.port))
                .appFont(size: 15, weight: .bold, design: .monospaced)
                .foregroundStyle(result.isOpen ? AppTheme.primaryText : AppTheme.tertiaryText)
                .frame(width: 56, alignment: .leading)

            if !result.serviceName.isEmpty {
                Text(verbatim: result.serviceName)
                    .appFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(result.isOpen ? accent : AppTheme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if result.isOpen {
                Text(verbatim: result.responseTime.fixed(0) + " ms")
                    .appFont(size: 12, weight: .medium, design: .monospaced)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            AppPill(text: result.isOpen ? "Open" : "Closed",
                    tint: result.isOpen ? AppTheme.ping : AppTheme.ink.opacity(0.45))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Tool Page Components

/// Icon tile + short description shown at the top of the tool's hero card.
private struct ToolHeroHeader: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .appFont(size: 24, weight: .semibold)
                .foregroundStyle(AppTheme.ink)
                .frame(width: 52, height: 52)
                .background(AppTheme.ink.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appFont(size: 19, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .appFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private extension View {
    /// Darkened inset so inputs and controls stay legible on the hero gradient.
    func heroInset() -> some View {
        background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
}

/// Card explaining why the last run failed.
private struct ToolErrorCard: View {
    let title: LocalizedStringKey
    let message: String
    var icon = "exclamationmark.triangle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconTile(systemName: icon, tint: AppTheme.danger)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                Text(verbatim: message)
                    .appFont(size: 13, weight: .regular, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .appCard()
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.danger.opacity(0.35), lineWidth: 1)
        )
    }
}

/// Selectable capsule used for options inside the hero card.
private struct HeroChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let selectedTint: Color
    var monospaced = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .appFont(size: 11, weight: .semibold)
            }
            Text(verbatim: title)
                .appFont(size: 13, weight: .semibold, design: monospaced ? .monospaced : .rounded)
        }
        .foregroundStyle(isSelected ? selectedTint : AppTheme.ink.opacity(0.85))
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(Capsule().fill(isSelected ? AppTheme.ink : Color.black.opacity(0.22)))
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    NavigationStack {
        PortScannerView()
    }
    .preferredColorScheme(.dark)
}
