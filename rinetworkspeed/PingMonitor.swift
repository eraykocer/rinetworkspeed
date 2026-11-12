//
//  PingMonitor.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import Foundation
import Combine

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
        guard let url = URL(string: "https://\(host)") else {
            return -1
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false

        let session = URLSession(configuration: configuration)
        // Sessions are not released until invalidated; one was leaked per ping.
        defer { session.finishTasksAndInvalidate() }
        let start = Date()

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...599).contains(httpResponse.statusCode) else {
                return -1
            }
            return Date().timeIntervalSince(start) * 1000
        } catch {
            return -1
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
