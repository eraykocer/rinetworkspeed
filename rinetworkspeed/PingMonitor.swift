//
//  PingMonitor.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import Foundation
import Combine
import Network

enum ConnectionStatus {
    case excellent
    case good
    case fair
    case poor
    case timeout
}

struct PingSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let latency: Double
}

@MainActor
final class PingMonitor: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var currentPing: Double = 0
    @Published var minPing: Double = 0
    @Published var maxPing: Double = 0
    @Published var avgPing: Double = 0
    @Published var packetsSent: Int = 0
    @Published var packetsLost: Int = 0
    @Published var packetLossPercent: Double = 0
    /// Mean absolute difference between consecutive successful samples (RFC 3550 style).
    @Published var jitter: Double = 0
    @Published var pingHistory: [PingSample] = []
    @Published var status: ConnectionStatus = .good

    // Router series, measured alongside the chosen host on Wi-Fi so a problem
    // can be placed on the Wi-Fi or beyond the router.

    /// Router address; nil when not on Wi-Fi.
    @Published private(set) var routerIP: String?
    /// Same window as `pingHistory`.
    @Published private(set) var routerHistory: [PingSample] = []
    /// Nil until the router answered, or when it does not answer at all.
    @Published private(set) var routerStats: LatencyStats?
    /// Nil when not on Wi-Fi.
    @Published private(set) var diagnosis: LatencyDiagnosis?

    private let interval: TimeInterval = 1
    private let timeout: TimeInterval = 3
    private let maxSamples = 60

    private var timer: Timer?
    private var currentHost: String = "1.1.1.1"
    /// Port the router answers on (open or refused); nil while unknown.
    private var routerPort: UInt16?
    private var routerSetupTask: Task<Void, Never>?

    /// Ports tried on the router. A refused connection also counts as an
    /// answer: the router replied, it just has nothing listening there.
    nonisolated static let routerPorts: [UInt16] = [80, 443, 53]

    deinit {
        timer?.invalidate()
        timer = nil
    }

    func start(host: String) {
        let sanitizedHost = sanitized(host: host)
        if currentHost != sanitizedHost {
            reset()
        }
        currentHost = sanitizedHost

        guard timer == nil else {
            isRunning = true
            return
        }

        isRunning = true
        setUpRouter()
        Task {
            await performPing()
        }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.performPing()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        routerSetupTask?.cancel()
        routerSetupTask = nil
        isRunning = false
    }

    func reset() {
        currentPing = 0
        minPing = 0
        maxPing = 0
        avgPing = 0
        packetsSent = 0
        packetsLost = 0
        packetLossPercent = 0
        jitter = 0
        pingHistory = []
        status = .good
        routerHistory = []
        routerStats = nil
        diagnosis = routerIP == nil ? nil : .collecting
    }

    func activeHost() -> String {
        currentHost
    }

    private func performPing() async {
        let host = currentHost
        let router = routerIP
        let port = routerPort
        let timeout = self.timeout

        // Both probes run at the same time so they see the same conditions.
        async let internetProbe = Self.tcpConnectTime(host: host, port: 443, timeout: timeout)
        async let routerProbe = Self.probeRouter(router, port: port, timeout: timeout)
        let latency = await internetProbe
        let routerLatency = await routerProbe

        // The host or network changed while the probes were in flight.
        guard host == currentHost, router == routerIP else { return }

        packetsSent += 1
        currentPing = latency
        if latency < 0 {
            packetsLost += 1
        }

        updateHistory(latency: latency)
        if let routerLatency {
            routerHistory.append(PingSample(timestamp: Date(), latency: routerLatency))
            if routerHistory.count > maxSamples {
                routerHistory.removeFirst(routerHistory.count - maxSamples)
            }
        }
        recalculateStats()
        status = status(for: latency)
    }

    nonisolated private static func probeRouter(_ router: String?, port: UInt16?, timeout: TimeInterval) async -> Double? {
        guard let router, let port else { return nil }
        return await tcpConnectTime(host: router, port: port, timeout: timeout, countRefusedAsReply: true)
    }

    /// Finds the router and a port it answers on. Called on every start, as
    /// the network may have changed; the router series stays empty when not
    /// on Wi-Fi.
    private func setUpRouter() {
        let details = WiFiInfoManager.localInterfaceDetails()
        guard details.ipAddress != nil, let router = details.routerIP else {
            routerSetupTask?.cancel()
            routerSetupTask = nil
            routerIP = nil
            routerPort = nil
            routerHistory = []
            routerStats = nil
            diagnosis = nil
            return
        }
        // Same router, and its port is known or still being looked up.
        if router == routerIP, routerPort != nil || routerSetupTask != nil { return }

        routerSetupTask?.cancel()
        routerIP = router
        routerPort = nil
        routerHistory = []
        routerStats = nil
        diagnosis = .collecting

        routerSetupTask = Task { [weak self] in
            let port = await Self.answeringPort(host: router)
            guard let self, !Task.isCancelled, self.routerIP == router else { return }
            self.routerPort = port
            self.routerSetupTask = nil
            self.recalculateStats()
        }
    }

    /// First of `routerPorts` the host answers on, or nil.
    nonisolated static func answeringPort(host: String, timeout: TimeInterval = 2) async -> UInt16? {
        for port in routerPorts {
            if await tcpConnectTime(host: host, port: port, timeout: timeout, countRefusedAsReply: true) >= 0 {
                return port
            }
        }
        return nil
    }

    /// Measures how long a TCP handshake takes (SYN → SYN-ACK), which is one
    /// network round trip. The previous HTTPS HEAD on a fresh session also
    /// included the TLS handshake and server time, inflating the value
    /// several times over. Hostname lookups are served from the system DNS
    /// cache after the first sample. With `countRefusedAsReply`, a refused
    /// connection (RST) also counts: it is a full round trip too, which lets
    /// routers without an open port be measured. Returns -1 when lost.
    nonisolated static func tcpConnectTime(
        host: String,
        port: UInt16,
        timeout: TimeInterval,
        countRefusedAsReply: Bool = false
    ) async -> Double {
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else { return -1 }

        let parameters = NWParameters.tcp
        parameters.preferNoProxies = true
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        let queue = DispatchQueue(label: "rinetworkspeed.ping.probe")

        return await withCheckedContinuation { continuation in
            let result = OnceContinuation(continuation)
            let start = DispatchTime.now().uptimeNanoseconds
            let elapsed = { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    result.resume(elapsed())
                    connection.cancel()
                case .waiting(let error), .failed(let error):
                    if countRefusedAsReply, case .posix(let code) = error, code == .ECONNREFUSED {
                        result.resume(elapsed())
                    } else {
                        result.resume(-1)
                    }
                    connection.cancel()
                default:
                    break
                }
            }

            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                result.resume(-1)
                connection.cancel()
            }
        }
    }

    private func updateHistory(latency: Double) {
        pingHistory.append(PingSample(timestamp: Date(), latency: latency))
        if pingHistory.count > maxSamples {
            pingHistory.removeFirst(pingHistory.count - maxSamples)
        }
    }

    private func recalculateStats() {
        let internet = LatencyStats(samples: pingHistory.map(\.latency))
        minPing = internet.minimum
        maxPing = internet.maximum
        avgPing = internet.average
        jitter = internet.jitter

        packetLossPercent = packetsSent == 0 ? 0 : (Double(packetsLost) / Double(packetsSent)) * 100

        guard routerIP != nil else {
            routerStats = nil
            diagnosis = nil
            return
        }
        if routerPort == nil && routerSetupTask == nil {
            // The router answered on none of the ports.
            routerStats = nil
            diagnosis = .routerSilent
            return
        }
        guard !routerHistory.isEmpty else {
            diagnosis = .collecting
            return
        }
        let router = LatencyStats(samples: routerHistory.map(\.latency))
        routerStats = router
        diagnosis = LatencyDiagnosis.evaluate(router: router, internet: internet)
    }

    private func status(for latency: Double) -> ConnectionStatus {
        if latency < 0 {
            return .timeout
        } else if latency < 20 {
            return .excellent
        } else if latency < 60 {
            return .good
        } else if latency < 150 {
            return .fair
        }
        return .poor
    }

    private func sanitized(host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/", with: "")
    }
}
