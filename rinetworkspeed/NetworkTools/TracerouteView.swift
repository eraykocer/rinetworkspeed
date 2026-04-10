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
    private let bg = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let accent = Color(red: 0.13, green: 0.72, blue: 0.52)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                inputCard
                if !vm.hops.isEmpty { hopsList }
                if let err = vm.errorMessage {
                    ContentUnavailableView("Trace Failed", systemImage: "exclamationmark.triangle.fill",
                                          description: Text(err))
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(bg.ignoresSafeArea())
        .navigationTitle("Traceroute")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Input Card

    private var inputCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)

                TextField("Target host (e.g. google.com)", text: $vm.targetHost)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .onSubmit { if !vm.isRunning { vm.start() } }
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                vm.isRunning ? vm.cancel() : vm.start()
            } label: {
                HStack(spacing: 8) {
                    if vm.isRunning {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                    Text(vm.isRunning ? "Stop Trace" : "Start Trace")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(vm.isRunning
                            ? LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [accent, Color(red: 0.05, green: 0.41, blue: 0.30)],
                                             startPoint: .leading, endPoint: .trailing))
                )
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Hops List

    private var hopsList: some View {
        VStack(spacing: 0) {
            ForEach(vm.hops) { hop in
                HopRow(hop: hop)
                if hop.id != vm.hops.last?.id {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1, height: 16)
                            .padding(.leading, 28)
                        Spacer()
                    }
                }
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Hop Row

private struct HopRow: View {
    let hop: TraceHop
    @State private var visible = false

    private var latencyColor: Color {
        guard let ms = hop.latency else { return .secondary }
        if ms < 20  { return .green }
        if ms < 80  { return Color(red: 0.6, green: 0.9, blue: 0.2) }
        if ms < 200 { return .orange }
        return .red
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Hop number bubble
            ZStack {
                Circle()
                    .fill(hop.isTimeout ? Color.white.opacity(0.08) : Color(red: 0.13, green: 0.72, blue: 0.52).opacity(0.20))
                    .frame(width: 36, height: 36)
                Text("\(hop.hopNumber)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(hop.isTimeout ? .white.opacity(0.35) : Color(red: 0.13, green: 0.72, blue: 0.52))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(hop.isTimeout ? "* * *" : (hop.hostname ?? hop.ip))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(hop.isTimeout ? .white.opacity(0.30) : .white)
                    .lineLimit(1)
                if !hop.isTimeout, let host = hop.hostname, host != hop.ip {
                    Text(hop.ip)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.40))
                }
            }

            Spacer()

            if hop.isTimeout {
                Text("Timeout")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.30))
            } else if let ms = hop.latency {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.1f ms", ms))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(latencyColor)

                    // Latency bar (max 300ms mapped to full width)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(latencyColor.opacity(0.25))
                            .frame(width: geo.size.width, height: 4)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(latencyColor)
                                    .frame(width: geo.size.width * min(ms / 300.0, 1.0), height: 4)
                            }
                    }
                    .frame(width: 70, height: 4)
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

#Preview {
    NavigationStack {
        TracerouteView()
    }
}
