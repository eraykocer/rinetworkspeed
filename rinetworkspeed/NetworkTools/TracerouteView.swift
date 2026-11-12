//
//  TracerouteView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Network
import Darwin
import Combine

// MARK: - Model

struct TraceHop: Identifiable {
    let id = UUID()
    var hopNumber: Int
    var ip: String
    var hostname: String?
    var latency: Double?     // ms — nil means timeout
    var isTimeout: Bool
}

// MARK: - ViewModel

@MainActor
final class TracerouteViewModel: ObservableObject {
    @Published var hops: [TraceHop] = []
    @Published var isRunning = false
    @Published var targetHost: String = "google.com"
    @Published var errorMessage: String?

    private var traceTask: Task<Void, Never>?

    func start() {
        let target = targetHost.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        isRunning = true
        hops = []
        errorMessage = nil

        traceTask = Task {
            await runTrace(target: target)
            isRunning = false
        }
    }

    func cancel() {
        traceTask?.cancel()
        isRunning = false
    }

    // MARK: - Trace Pipeline

    private func runTrace(target: String) async {
        // ── Hop 1: Local Gateway ──────────────────────────────────────────
        let gwHop = await discoverGateway()
        appendHop(gwHop ?? TraceHop(hopNumber: 1, ip: "* * *", hostname: "Local Gateway",
                                     latency: nil, isTimeout: true))
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(250))

        // ── Hop 2: Cloudflare (upstream/ISP boundary) ─────────────────────
        let cfHop = await probe(ip: "1.1.1.1", hopNumber: 2,
                                 fallbackLabel: "Cloudflare DNS")
        appendHop(cfHop)
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(250))

        // ── Hop 3: Google DNS (backbone) ──────────────────────────────────
        let googleHop = await probe(ip: "8.8.8.8", hopNumber: 3,
                                     fallbackLabel: "Google DNS")
        appendHop(googleHop)
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(250))

        // ── Hop 4: Destination ────────────────────────────────────────────
        let isIP = target.split(separator: ".").count == 4 &&
                   target.split(separator: ".").allSatisfy { Int($0) != nil }
        if isIP {
            let destHop = await probe(ip: target, hopNumber: 4, fallbackLabel: target)
            appendHop(destHop)
        } else {
            // Resolve then probe
            if let ip = await Self.resolveHost(target) {
                let destHop = await probe(ip: ip, hopNumber: 4, fallbackLabel: target)
                var hop = destHop
                // Prefer showing target domain as hostname
                if hop.hostname == nil || hop.hostname == target { hop.hostname = target }
                appendHop(hop)
            } else {
                appendHop(TraceHop(hopNumber: 4, ip: "* * *",
                                   hostname: target, latency: nil, isTimeout: true))
                errorMessage = "Could not resolve \(target)"
            }
        }
    }

    private func appendHop(_ hop: TraceHop) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            hops.append(hop)
        }
    }

    // MARK: - Gateway Discovery

    private func discoverGateway() async -> TraceHop? {
        let candidates = ["192.168.1.1", "192.168.0.1", "10.0.0.1",
                          "10.1.1.1", "172.16.0.1", "192.168.2.1"]
        for ip in candidates {
            let (ok, ms) = await tcpProbe(ip: ip, port: 80)
            if ok {
                let hostname = await IPScannerViewModel.reverseDNS(ip)
                return TraceHop(hopNumber: 1, ip: ip,
                                hostname: hostname ?? "Local Gateway",
                                latency: ms, isTimeout: false)
            }
        }
        return nil
    }

    // MARK: - Generic Host Probe

    private func probe(ip: String, hopNumber: Int, fallbackLabel: String) async -> TraceHop {
        // Try twice on different ports for a stable average
        var collected: [Double] = []
        for port in [UInt16(80), UInt16(443)] {
            let (ok, ms) = await tcpProbe(ip: ip, port: port)
            if ok { collected.append(ms) }
        }

        if collected.isEmpty {
            return TraceHop(hopNumber: hopNumber, ip: ip,
                            hostname: fallbackLabel, latency: nil, isTimeout: true)
        }
        let avg = collected.reduce(0, +) / Double(collected.count)
        let hostname = await IPScannerViewModel.reverseDNS(ip) ?? fallbackLabel
        return TraceHop(hopNumber: hopNumber, ip: ip,
                        hostname: hostname, latency: avg, isTimeout: false)
    }

    // MARK: - TCP Probe

    private func tcpProbe(ip: String, port: UInt16) async -> (Bool, Double) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return (false, 0) }
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)

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
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                conn.cancel()
                box.resume(returning: (false, 0))
            }
        }
    }

    // MARK: - DNS Resolution

    static func resolveHost(_ hostname: String) async -> String? {
        await Task.detached(priority: .utility) {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_STREAM
            var res: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(hostname, nil, &hints, &res) == 0, let first = res else { return nil }
            defer { freeaddrinfo(res) }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sa = first.pointee.ai_addr!.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            guard inet_ntop(AF_INET, &sa.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buf)
        }.value
    }
}

// MARK: - Thread-safe Box

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

// MARK: - Main View

struct TracerouteView: View {
    @StateObject private var vm = TracerouteViewModel()
    private let accent = Color(red: 0.13, green: 0.72, blue: 0.52)
    private let accentDeep = Color(red: 0.05, green: 0.41, blue: 0.30)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                heroCard

                if !vm.hops.isEmpty || vm.isRunning {
                    hopsSection
                }

                if let err = vm.errorMessage {
                    ToolErrorCard(title: "Trace Failed", message: err)
                } else if vm.hops.isEmpty && !vm.isRunning {
                    AppEmptyState(
                        icon: "point.3.connected.trianglepath.dotted",
                        title: "No Trace Yet",
                        message: "Enter a host and start a trace to see each hop along the route."
                    )
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .appPageBackground()
        .navigationTitle("Traceroute")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ToolHeroHeader(
                icon: "point.3.connected.trianglepath.dotted",
                title: "Hop-by-hop path analysis",
                subtitle: "Probe each hop on the way to a host and measure its latency."
            )

            AppInputField(icon: "globe", placeholder: "Target host (e.g. google.com)", text: $vm.targetHost) {
                if !vm.isRunning { vm.start() }
            }
            .heroInset()

            Button {
                vm.isRunning ? vm.cancel() : vm.start()
            } label: {
                HStack(spacing: 8) {
                    if vm.isRunning {
                        ProgressView().tint(accentDeep)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(vm.isRunning ? "Stop Trace" : "Start Trace")
                }
            }
            .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, colors: [accent, accentDeep]))
        }
        .appHeroCard(colors: [accent, accentDeep])
    }

    // MARK: - Hops Section

    private var hopsSection: some View {
        AppSection("Route") {
            ForEach(vm.hops) { hop in
                HopRow(hop: hop, accent: accent)
                if hop.id != vm.hops.last?.id || vm.isRunning {
                    AppRowDivider()
                }
            }

            if vm.isRunning {
                HStack(spacing: 14) {
                    ProgressView()
                        .tint(accent)
                        .frame(width: 40, height: 40)
                    Text("Probing next hop…")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - Hop Row

private struct HopRow: View {
    let hop: TraceHop
    let accent: Color
    @State private var visible = false

    private var latencyColor: Color {
        guard let ms = hop.latency else { return AppTheme.secondaryText }
        if ms < 20  { return AppTheme.ping }
        if ms < 80  { return Color(red: 0.6, green: 0.9, blue: 0.2) }
        if ms < 200 { return AppTheme.upload }
        return AppTheme.danger
    }

    private var tileFill: AnyShapeStyle {
        hop.isTimeout
            ? AnyShapeStyle(Color.white.opacity(0.06))
            : AnyShapeStyle(LinearGradient(colors: [accent, accent.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Hop number tile
            Text(verbatim: "\(hop.hopNumber)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(hop.isTimeout ? AppTheme.tertiaryText : .white)
                .frame(width: 40, height: 40)
                .background(tileFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(hop.isTimeout ? "* * *" : (hop.hostname ?? hop.ip))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(hop.isTimeout ? AppTheme.tertiaryText : AppTheme.primaryText)
                    .lineLimit(1)
                if !hop.isTimeout, let host = hop.hostname, host != hop.ip {
                    Text(hop.ip)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryText)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            if hop.isTimeout {
                AppPill(text: "Timeout", tint: .white.opacity(0.55))
            } else if let ms = hop.latency {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(String(format: "%.1f ms", ms))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(latencyColor)

                    // Latency bar (max 300ms mapped to full width)
                    Capsule()
                        .fill(latencyColor.opacity(0.22))
                        .frame(width: 64, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(latencyColor)
                                .frame(width: 64 * min(ms / 300.0, 1.0), height: 4)
                        }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(visible ? 1 : 0)
        .offset(x: visible ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.05 * Double(hop.hopNumber))) {
                visible = true
            }
        }
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
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
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
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Text(verbatim: message)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
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

#Preview {
    NavigationStack {
        TracerouteView()
    }
    .preferredColorScheme(.dark)
}
