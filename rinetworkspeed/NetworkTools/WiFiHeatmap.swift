//
//  WiFiHeatmap.swift
//  rinetworkspeed
//
//  Wi-Fi heatmap: measurements placed on a floor plan (a photo of a plan or a
//  blank grid), coloured by interpolating between them. Each measurement
//  pings the router, optionally runs a short download and attaches a Wi-Fi
//  signal reading from the Shortcuts bridge.
//

import Foundation
import Combine
import UIKit

// MARK: - Model

nonisolated struct HeatmapPoint: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    /// Position on the plan, 0…1 from the top-left corner.
    var x: Double
    var y: Double
    var date = Date()
    /// Router probes: average and jitter in ms, loss 0…1.
    var routerLatency: Double?
    var routerJitter: Double?
    var routerLoss: Double = 0
    var downloadMbps: Double?
    /// dBm, from the Wi-Fi signal shortcut.
    var rssi: Int?
}

nonisolated struct WiFiHeatmapSurvey: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    /// File name of the plan image in the heatmap folder; nil for a blank grid.
    var planImageFile: String?
    /// Width divided by height of the plan.
    var planAspectRatio: Double = 0.75
    /// Router position, 0…1, when the user marked it.
    var routerX: Double?
    var routerY: Double?
    var points: [HeatmapPoint] = []
}

// MARK: - Metrics

nonisolated enum HeatmapMetric: String, CaseIterable, Identifiable, Sendable {
    /// Round trips to the router: shows the quality of the Wi-Fi link itself.
    case router
    case download
    case signal

    var id: String { rawValue }

    /// 0 (bad) … 1 (good) for one point; nil when the point lacks the value.
    /// `bestDownload` is the highest download of the survey, as download is
    /// compared between spots rather than against a fixed scale.
    func score(_ point: HeatmapPoint, bestDownload: Double?) -> Double? {
        switch self {
        case .router:
            guard let latency = point.routerLatency else { return point.routerLoss >= 1 ? 0 : nil }
            // Jitter and loss hurt more than a steady delay.
            let effective = latency + 2 * (point.routerJitter ?? 0) + 200 * point.routerLoss
            return Self.clamp((60 - effective) / (60 - 3))
        case .download:
            guard let mbps = point.downloadMbps, let best = bestDownload, best > 0 else { return nil }
            return Self.clamp(mbps / best)
        case .signal:
            guard let rssi = point.rssi else { return nil }
            // -45 dBm and stronger is full, -80 dBm and weaker is empty.
            return Self.clamp(Double(rssi + 80) / 35)
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

/// Four bands, matching the signal quality labels elsewhere in the app.
nonisolated enum HeatmapLevel: Int, CaseIterable, Sendable {
    case weak, fair, good, excellent

    init(score: Double) {
        switch score {
        case 0.75...: self = .excellent
        case 0.5..<0.75: self = .good
        case 0.25..<0.5: self = .fair
        default: self = .weak
        }
    }
}

// MARK: - Interpolation and advice

nonisolated enum HeatmapMath {
    /// Points further than this (in plan units, 0…1) leave a spot uncoloured.
    static let reach = 0.3

    /// Inverse-distance-weighted score at (x, y), or nil when no scored point
    /// is within `reach`. `aspectRatio` (width / height) keeps distances true
    /// on a non-square plan.
    static func interpolate(x: Double, y: Double, samples: [(x: Double, y: Double, score: Double)],
                            aspectRatio: Double) -> Double? {
        var weighted = 0.0
        var totalWeight = 0.0
        var nearest = Double.infinity
        for sample in samples {
            let dx = (x - sample.x) * aspectRatio
            let dy = y - sample.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < 1e-6 { return sample.score }
            nearest = min(nearest, distance)
            let weight = 1 / (distance * distance)
            weighted += weight * sample.score
            totalWeight += weight
        }
        guard totalWeight > 0, nearest <= reach * max(1, aspectRatio) else { return nil }
        return weighted / totalWeight
    }

    /// Where a mesh point or repeater would help: halfway between the router
    /// and the weakest spot, when that spot scores below `fair`. A rule of
    /// thumb, not a radio simulation.
    static func meshSuggestion(router: (x: Double, y: Double)?,
                               samples: [(x: Double, y: Double, score: Double)]) -> (x: Double, y: Double)? {
        guard let router, let weakest = samples.min(by: { $0.score < $1.score }),
              weakest.score < 0.5 else { return nil }
        return ((router.x + weakest.x) / 2, (router.y + weakest.y) / 2)
    }
}

extension WiFiHeatmapSurvey {
    nonisolated var bestDownload: Double? {
        points.compactMap(\.downloadMbps).max()
    }

    nonisolated func samples(for metric: HeatmapMetric) -> [(x: Double, y: Double, score: Double)] {
        let best = bestDownload
        return points.compactMap { point in
            metric.score(point, bestDownload: best).map { (point.x, point.y, $0) }
        }
    }

    nonisolated var router: (x: Double, y: Double)? {
        guard let routerX, let routerY else { return nil }
        return (routerX, routerY)
    }
}

// MARK: - Store

@MainActor
final class WiFiHeatmapStore: ObservableObject {
    static let shared = WiFiHeatmapStore()

    /// Newest first.
    @Published private(set) var surveys: [WiFiHeatmapSurvey] = []

    private let directory: URL
    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Heatmaps", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("heatmaps.json")
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([WiFiHeatmapSurvey].self, from: data) {
            surveys = stored
        }
    }

    func survey(id: UUID) -> WiFiHeatmapSurvey? {
        surveys.first { $0.id == id }
    }

    /// Creates a survey; `plan` is stored as a JPEG next to the data.
    @discardableResult
    func create(named name: String, plan: UIImage?) -> WiFiHeatmapSurvey {
        var survey = WiFiHeatmapSurvey(name: name)
        if let plan, plan.size.height > 0, let data = plan.jpegData(compressionQuality: 0.85) {
            let file = "plan-\(survey.id.uuidString).jpg"
            if (try? data.write(to: directory.appendingPathComponent(file), options: .atomic)) != nil {
                survey.planImageFile = file
                survey.planAspectRatio = plan.size.width / plan.size.height
            }
        }
        surveys.insert(survey, at: 0)
        save()
        return survey
    }

    func update(_ survey: WiFiHeatmapSurvey) {
        guard let index = surveys.firstIndex(where: { $0.id == survey.id }) else { return }
        surveys[index] = survey
        save()
    }

    func delete(id: UUID) {
        if let file = survey(id: id)?.planImageFile {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
        surveys.removeAll { $0.id == id }
        save()
    }

    func planImage(for survey: WiFiHeatmapSurvey) -> UIImage? {
        guard let file = survey.planImageFile else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(file).path)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(surveys) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Measuring one spot

@MainActor
final class HeatmapMeasurer: ObservableObject {
    enum Phase: Equatable {
        case idle
        case router
        case download
        case signal
    }

    @Published private(set) var phase: Phase = .idle
    /// Router and the port it answers on, found once per screen.
    private var router: (host: String, port: UInt16)?

    var isMeasuring: Bool { phase != .idle }

    /// Measures at the current spot. Returns nil when not on Wi-Fi.
    func measure(at x: Double, y: Double, includeDownload: Bool, includeSignal: Bool) async -> HeatmapPoint? {
        defer { phase = .idle }
        var point = HeatmapPoint(x: x, y: y)

        phase = .router
        if router == nil {
            let details = WiFiInfoManager.localInterfaceDetails()
            guard details.ipAddress != nil, let host = details.routerIP else { return nil }
            if let port = await PingMonitor.answeringPort(host: host) {
                router = (host, port)
            }
        }
        if let router {
            var samples: [Double] = []
            for _ in 0..<10 {
                samples.append(await PingMonitor.tcpConnectTime(host: router.host, port: router.port,
                                                                timeout: 1, countRefusedAsReply: true))
                try? await Task.sleep(for: .milliseconds(150))
            }
            let stats = LatencyStats(samples: samples)
            point.routerLoss = stats.lossShare
            if stats.sent > stats.lost {
                point.routerLatency = stats.average
                point.routerJitter = stats.jitter
            }
        }

        if includeDownload {
            phase = .download
            point.downloadMbps = await QuickDownloadProbe.measure()
        }

        if includeSignal {
            phase = .signal
            point.rssi = await readSignal()
        }
        return point
    }

    /// Runs the signal shortcut and waits for its answer (up to 20 s).
    private func readSignal() async -> Int? {
        let store = WiFiSignalStore.shared
        let requestedAt = Date()
        store.requestReading()
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(500))
            if let latest = store.latest, latest.date >= requestedAt {
                return latest.rssi
            }
        }
        return nil
    }
}

/// A 3-second download over a few parallel connections to the speed test
/// server: enough to compare spots, not a full speed test.
nonisolated final class QuickDownloadProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Int64 = 0

    private var total: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        bytes += Int64(data.count)
        lock.unlock()
    }

    /// Megabits per second over the last two seconds, or nil when nothing arrived.
    static func measure(streams: Int = 4, duration: TimeInterval = 3) async -> Double? {
        let probe = QuickDownloadProbe()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = streams
        let session = URLSession(configuration: configuration, delegate: probe, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        for _ in 0..<streams {
            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=100000000&measId=\(UUID().uuidString)") else { return nil }
            session.dataTask(with: url).resume()
        }

        // The first second covers connection setup and TCP slow start.
        try? await Task.sleep(for: .seconds(1))
        let startBytes = probe.total
        let start = ProcessInfo.processInfo.systemUptime
        try? await Task.sleep(for: .seconds(duration - 1))
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let received = probe.total - startBytes
        guard received > 0, elapsed > 0 else { return nil }
        return Double(received) * 8 / elapsed / 1_000_000
    }
}
