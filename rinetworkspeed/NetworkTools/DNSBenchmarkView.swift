//
//  DNSBenchmarkView.swift
//  rinetworkspeed
//
//  Compares how fast DNS servers answer from this network (the router, which
//  usually forwards to the provider, and public resolvers) and can set the
//  fastest public one up as encrypted DNS (DNS over HTTPS) for the whole
//  device with NEDNSSettingsManager.
//

import SwiftUI
import Combine
import NetworkExtension
import Darwin

// MARK: - DNS wire format

nonisolated enum DNSWire {
    /// A standard query with recursion desired.
    static func query(id: UInt16, name: String, type: UInt16 = 1) -> [UInt8]? {
        var packet: [UInt8] = [UInt8(id >> 8), UInt8(id & 0xFF), 0x01, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            guard !bytes.isEmpty, bytes.count < 64 else { return nil }
            packet.append(UInt8(bytes.count))
            packet += bytes
        }
        packet.append(0)
        packet += [UInt8(type >> 8), UInt8(type & 0xFF), 0x00, 0x01]
        return packet
    }

    /// Response code and answer count, when `data` answers query `id`.
    static func parse(_ data: [UInt8], id: UInt16) -> (responseCode: Int, answers: Int)? {
        guard data.count >= 12,
              (UInt16(data[0]) << 8 | UInt16(data[1])) == id,
              data[2] & 0x80 != 0 else { return nil }
        return (Int(data[3] & 0x0F), Int(UInt16(data[6]) << 8 | UInt16(data[7])))
    }

    /// Round trip in ms for one query over UDP; nil on timeout or a failed answer.
    static func lookup(_ name: String, server: String, timeout: TimeInterval = 2) async -> Double? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: lookupBlocking(name, server: server, timeout: timeout))
            }
        }
    }

    private static func lookupBlocking(_ name: String, server: String, timeout: TimeInterval) -> Double? {
        let id = UInt16.random(in: 0...UInt16.max)
        guard let packet = query(id: id, name: name) else { return nil }
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = UInt16(53).bigEndian
        guard inet_pton(AF_INET, server, &target.sin_addr) == 1 else { return nil }

        let start = DispatchTime.now().uptimeNanoseconds
        let sent = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { return nil }

        let deadline = start + UInt64(timeout * 1_000_000_000)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return nil }
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, Int32(max(1, Double(deadline - now) / 1_000_000))) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 1500)
            let capacity = buffer.count
            let count = recv(descriptor, &buffer, capacity, 0)
            guard count > 0, let answer = parse(Array(buffer.prefix(count)), id: id) else { continue }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            // NOERROR or NXDOMAIN both mean the server answered.
            return answer.responseCode == 0 || answer.responseCode == 3 ? elapsed : nil
        }
    }
}

// MARK: - Resolvers

nonisolated struct DNSProvider: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// Plain DNS address used for the benchmark.
    let address: String
    /// DNS-over-HTTPS settings; nil for the router.
    let dohServers: [String]
    let dohURL: String?

    static let publicProviders: [DNSProvider] = [
        DNSProvider(id: "cloudflare", name: "Cloudflare", address: "1.1.1.1",
                    dohServers: ["1.1.1.1", "1.0.0.1"], dohURL: "https://cloudflare-dns.com/dns-query"),
        DNSProvider(id: "google", name: "Google", address: "8.8.8.8",
                    dohServers: ["8.8.8.8", "8.8.4.4"], dohURL: "https://dns.google/dns-query"),
        DNSProvider(id: "quad9", name: "Quad9", address: "9.9.9.9",
                    dohServers: ["9.9.9.9", "149.112.112.112"], dohURL: "https://dns.quad9.net/dns-query"),
        DNSProvider(id: "adguard", name: "AdGuard", address: "94.140.14.14",
                    dohServers: ["94.140.14.14", "94.140.15.15"], dohURL: "https://dns.adguard-dns.com/dns-query"),
        DNSProvider(id: "opendns", name: "OpenDNS", address: "208.67.222.222",
                    dohServers: ["208.67.222.222", "208.67.220.220"], dohURL: "https://doh.opendns.com/dns-query")
    ]

    static func router(_ address: String) -> DNSProvider {
        DNSProvider(id: "router", name: String(localized: "Your router / provider"), address: address, dohServers: [], dohURL: nil)
    }
}

nonisolated struct DNSBenchmarkResult: Identifiable, Equatable, Sendable {
    var id: String { provider.id }
    let provider: DNSProvider
    /// Every lookup, nil when it failed.
    let samples: [Double?]

    var median: Double? {
        let answered = samples.compactMap { $0 }.sorted()
        guard !answered.isEmpty else { return nil }
        let middle = answered.count / 2
        return answered.count.isMultiple(of: 2) ? (answered[middle - 1] + answered[middle]) / 2 : answered[middle]
    }

    var successShare: Double {
        samples.isEmpty ? 0 : Double(samples.compactMap { $0 }.count) / Double(samples.count)
    }

    /// Fastest public resolver that answered nearly everything.
    static func bestPublic(_ results: [DNSBenchmarkResult]) -> DNSBenchmarkResult? {
        results
            .filter { $0.provider.dohURL != nil && $0.successShare >= 0.9 && $0.median != nil }
            .min { ($0.median ?? .infinity) < ($1.median ?? .infinity) }
    }
}

// MARK: - ViewModel

@MainActor
final class DNSBenchmarkViewModel: ObservableObject {
    /// Popular names: answers come from the resolver's cache, which is what
    /// most everyday lookups hit. The first round may also show uncached times.
    static let domains = ["google.com", "youtube.com", "instagram.com", "whatsapp.net",
                          "netflix.com", "apple.com", "wikipedia.org", "amazon.com"]
    static let rounds = 2

    @Published private(set) var results: [DNSBenchmarkResult] = []
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var encryptedDNSName: String?
    @Published private(set) var encryptedDNSEnabled = false
    @Published private(set) var settingsError: String?

    private var task: Task<Void, Never>?

    func start() {
        task?.cancel()
        results = []
        progress = 0
        isRunning = true
        task = Task {
            defer { isRunning = false }
            var providers = DNSProvider.publicProviders
            if let router = WiFiInfoManager.localInterfaceDetails().routerIP {
                providers.insert(.router(router), at: 0)
            }
            let total = Double(providers.count * Self.domains.count * Self.rounds)
            var done = 0.0
            var collected: [DNSBenchmarkResult] = []
            // One resolver at a time, so they don't compete for the link.
            for provider in providers {
                var samples: [Double?] = []
                for _ in 0..<Self.rounds {
                    for domain in Self.domains {
                        guard !Task.isCancelled else { return }
                        samples.append(await DNSWire.lookup(domain, server: provider.address))
                        done += 1
                        progress = done / total
                    }
                }
                collected.append(DNSBenchmarkResult(provider: provider, samples: samples))
                results = collected.sorted { ($0.median ?? .infinity) < ($1.median ?? .infinity) }
            }
        }
    }

    func cancel() {
        task?.cancel()
        isRunning = false
    }

    // MARK: Encrypted DNS

    func loadEncryptedDNS() async {
        let manager = NEDNSSettingsManager.shared()
        try? await manager.loadFromPreferences()
        encryptedDNSName = manager.dnsSettings == nil ? nil : manager.localizedDescription
        encryptedDNSEnabled = manager.isEnabled
    }

    func useEncryptedDNS(_ provider: DNSProvider) async {
        guard let urlString = provider.dohURL, let url = URL(string: urlString) else { return }
        settingsError = nil
        let manager = NEDNSSettingsManager.shared()
        do {
            try await manager.loadFromPreferences()
            let settings = NEDNSOverHTTPSSettings(servers: provider.dohServers)
            settings.serverURL = url
            manager.dnsSettings = settings
            manager.localizedDescription = "RiNetwork – \(provider.name)"
            try await manager.saveToPreferences()
        } catch {
            settingsError = error.localizedDescription
        }
        await loadEncryptedDNS()
    }

    func removeEncryptedDNS() async {
        settingsError = nil
        let manager = NEDNSSettingsManager.shared()
        do {
            try await manager.loadFromPreferences()
            try await manager.removeFromPreferences()
        } catch {
            settingsError = error.localizedDescription
        }
        await loadEncryptedDNS()
    }
}

// MARK: - View

struct DNSBenchmarkView: View {
    @StateObject private var vm = DNSBenchmarkViewModel()
    private let tint = Color(red: 0.98, green: 0.62, blue: 0.16)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                ToolHero(icon: "speedometer", title: "DNS Benchmark",
                         subtitle: "Every website visit starts with a name lookup. See which DNS server answers fastest from this network.",
                         tint: tint, isRunning: vm.isRunning, startTitle: "Run Benchmark") {
                    vm.isRunning ? vm.cancel() : vm.start()
                }

                if vm.isRunning {
                    ProgressView(value: vm.progress).tint(tint)
                }

                if !vm.results.isEmpty {
                    resultsSection
                }

                encryptedSection
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .appPageBackground()
        .navigationTitle("DNS Benchmark")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadEncryptedDNS() }
        .onDisappear { vm.cancel() }
    }

    private var resultsSection: some View {
        let fastest = vm.results.first?.median
        return AppSection("Results", footer: "Median of \(DNSBenchmarkViewModel.domains.count * DNSBenchmarkViewModel.rounds) lookups of popular websites over plain DNS. Encrypted DNS adds little once its connection is open.") {
            ForEach(vm.results) { result in
                let isFastest = result.median != nil && result.median == fastest && !vm.isRunning
                CheckRow(
                    status: result.successShare < 0.9 ? .warning : (isFastest ? .pass : .info),
                    title: Text(verbatim: result.provider.name),
                    detail: result.successShare < 1
                        ? Text("\(Int((1 - result.successShare) * 100))% of lookups failed")
                        : Text(verbatim: result.provider.address),
                    value: result.median.map { "\($0.fixed(0)) ms" } ?? "—"
                )
                if result.id != vm.results.last?.id { AppRowDivider(leadingInset: 16) }
            }
        }
    }

    private var encryptedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("Encrypted DNS")
            VStack(alignment: .leading, spacing: 12) {
                if let name = vm.encryptedDNSName {
                    if vm.encryptedDNSEnabled {
                        Text("\(name) is set up and turned on.")
                    } else {
                        Text("\(name) is set up but not turned on. Turn it on in Settings → General → VPN & Device Management → DNS.")
                    }
                    Button("Remove Encrypted DNS", role: .destructive) {
                        Task { await vm.removeEncryptedDNS() }
                    }
                } else {
                    Text("Encrypted DNS keeps this network and your provider from seeing or changing which websites you look up.")
                }

                if let best = DNSBenchmarkResult.bestPublic(vm.results), !vm.isRunning {
                    Button {
                        Task { await vm.useEncryptedDNS(best.provider) }
                    } label: {
                        Label("Use \(best.provider.name) Encrypted DNS", systemImage: "lock.fill")
                    }
                    .buttonStyle(AppSecondaryButtonStyle())
                    Text("After setting it up, turn it on in Settings → General → VPN & Device Management → DNS. A VPN or a configuration profile can override it.")
                        .appFont(size: 12, weight: .regular, design: .rounded)
                        .foregroundStyle(AppTheme.tertiaryText)
                } else if vm.results.isEmpty {
                    Text("Run the benchmark to get a recommendation.")
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if let error = vm.settingsError {
                    Text(verbatim: error)
                        .appFont(size: 12, weight: .regular, design: .rounded)
                        .foregroundStyle(AppTheme.danger)
                }
            }
            .appFont(size: 14, weight: .regular, design: .rounded)
            .foregroundStyle(AppTheme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        }
    }
}
