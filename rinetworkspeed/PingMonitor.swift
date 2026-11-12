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

    private let interval: TimeInterval = 1
    private let timeout: TimeInterval = 3
    private let maxSamples = 60

    private var timer: Timer?
    private var currentHost: String = "1.1.1.1"

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
    }

    func activeHost() -> String {
        currentHost
    }

    private func performPing() async {
        let host = currentHost
        packetsSent += 1

        let latency = await measurePing(host: host)
        currentPing = latency

        if latency < 0 {
            packetsLost += 1
        }

        updateHistory(latency: latency)
        recalculateStats()
        status = status(for: latency)
    }

    private func measurePing(host: String) async -> Double {
        await Self.tcpConnectTime(host: host, port: 443, timeout: timeout)
    }

    /// Measures how long a TCP handshake takes (SYN → SYN-ACK), which is one
    /// network round trip. The previous HTTPS HEAD on a fresh session also
    /// included the TLS handshake and server time, inflating the value
    /// several times over. Hostname lookups are served from the system DNS
    /// cache after the first sample.
    nonisolated static func tcpConnectTime(host: String, port: UInt16, timeout: TimeInterval) async -> Double {
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else { return -1 }

        let parameters = NWParameters.tcp
        parameters.preferNoProxies = true
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        let queue = DispatchQueue(label: "rinetworkspeed.ping.probe")

        return await withCheckedContinuation { continuation in
            let result = OnceContinuation(continuation)
            let start = DispatchTime.now().uptimeNanoseconds

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    result.resume(elapsed)
                    connection.cancel()
                case .waiting, .failed:
                    result.resume(-1)
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
        let validLatencies = pingHistory.map(\.latency).filter { $0 >= 0 }

        minPing = validLatencies.min() ?? 0
        maxPing = validLatencies.max() ?? 0
        avgPing = validLatencies.isEmpty ? 0 : validLatencies.reduce(0, +) / Double(validLatencies.count)

        let deltas = zip(validLatencies.dropFirst(), validLatencies).map { abs($0 - $1) }
        jitter = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count)

        packetLossPercent = packetsSent == 0 ? 0 : (Double(packetsLost) / Double(packetsSent)) * 100
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
