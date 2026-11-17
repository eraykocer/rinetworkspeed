//
//  SpeedTestManager.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import Foundation
import Combine
import os

enum SpeedTestState {
    case idle
    case pingTesting
    case downloadTesting
    case transitionToUpload
    case uploadTesting
    case finished
    case failed
}

struct SpeedTestResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    /// Bytes per second.
    let downloadSpeed: Double
    let uploadSpeed: Double
    /// Milliseconds.
    let ping: Double
    // Optional so results saved by earlier versions still decode.
    var jitter: Double?
    var connection: ConnectionKind?
    var ssid: String?
    var isp: String?
    /// Median latency (ms) measured on a separate connection while the
    /// download or upload phase was running. Nil for results recorded before
    /// latency under load was measured, or when too few probes came back.
    var loadedLatencyDownload: Double?
    var loadedLatencyUpload: Double?
    /// Cellular tests only: "5G", "5G NSA", "4G"… and the place, rounded to
    /// about 100 m, when location access was granted.
    var radioTechnology: String?
    var latitude: Double?
    var longitude: Double?

    init(
        id: UUID = UUID(),
        date: Date,
        downloadSpeed: Double,
        uploadSpeed: Double,
        ping: Double,
        jitter: Double? = nil,
        connection: ConnectionKind? = nil,
        ssid: String? = nil,
        isp: String? = nil,
        loadedLatencyDownload: Double? = nil,
        loadedLatencyUpload: Double? = nil,
        radioTechnology: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.ping = ping
        self.jitter = jitter
        self.connection = connection
        self.ssid = ssid
        self.isp = isp
        self.loadedLatencyDownload = loadedLatencyDownload
        self.loadedLatencyUpload = loadedLatencyUpload
        self.radioTechnology = radioTechnology
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Byte Counter

/// Thread-safe byte counter shared by all parallel streams of a phase.
/// Delegate callbacks add to it directly on their own queues, so no
/// per-chunk hop to the main actor is needed (that was a bottleneck at
/// gigabit speeds).
nonisolated private final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Int64 = 0
    private var failures: Int = 0

    func add(_ count: Int64) {
        lock.lock()
        bytes += count
        lock.unlock()
    }

    func recordFailure() {
        lock.lock()
        failures += 1
        lock.unlock()
    }

    var total: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }

    var failureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return failures
    }
}

// MARK: - Transfer Stream

nonisolated private enum TransferKind: Equatable, Sendable {
    case download
    case upload
}

/// One parallel transfer stream. Owns its own URLSession so each stream gets
/// its own TCP connection (a shared session would multiplex every request
/// over a single HTTP/2 connection, which caps throughput on fast links).
/// When a request finishes, the stream immediately issues the next one until
/// it is stopped — the phase is time-boxed, not size-boxed.
nonisolated private final class TransferStream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private static let downloadChunkBytes: Int64 = 50_000_000
    private static let uploadPayload = Data(count: 10_000_000)
    private static let maxFailures = 10

    private let kind: TransferKind
    private let counter: ByteCounter
    private let lock = NSLock()
    private var session: URLSession?
    private var isStopped = false
    private var failures = 0

    init(kind: TransferKind, counter: ByteCounter) {
        self.kind = kind
        self.counter = counter
        super.init()

        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func start() {
        startNextRequest()
    }

    func stop() {
        lock.lock()
        isStopped = true
        let session = self.session
        self.session = nil
        lock.unlock()
        // Also breaks the session → delegate retain cycle.
        session?.invalidateAndCancel()
    }

    private func startNextRequest() {
        lock.lock()
        guard !isStopped, let session else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Random query value defeats any intermediate caching.
        let measureID = UUID().uuidString
        switch kind {
        case .download:
            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(Self.downloadChunkBytes)&measId=\(measureID)") else { return }
            session.dataTask(with: URLRequest(url: url)).resume()
        case .upload:
            guard let url = URL(string: "https://speed.cloudflare.com/__up?measId=\(measureID)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            session.uploadTask(with: request, from: Self.uploadPayload).resume()
        }
    }

    // Reject non-2xx HTTP responses so a broken endpoint is reported as a failure.
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if kind == .download {
            counter.add(Int64(data.count))
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        if kind == .upload {
            counter.add(bytesSent)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let stopped = isStopped
        lock.unlock()
        guard !stopped else { return }

        let statusOK = (task.response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        if error == nil && statusOK {
            startNextRequest()
            return
        }

        counter.recordFailure()
        failures += 1
        guard failures < Self.maxFailures else { return }
        // Brief back-off before retrying a failed request.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startNextRequest()
        }
    }
}

// MARK: - Latency Probe

/// Measures HTTP round trips to the speed test server on a connection of its
/// own. Idle latency (before the transfers) and latency under load (while
/// they run) both use it, so the two values are comparable. `@concurrent`
/// keeps the timing off the main actor, where UI updates would add delay.
nonisolated private final class LatencyProbe: @unchecked Sendable {
    /// Seconds before a probe counts as timed out.
    let timeout: TimeInterval
    private let session: URLSession

    init(timeout: TimeInterval = 5) {
        self.timeout = timeout
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: config)
    }

    func invalidate() {
        session.invalidateAndCancel()
    }

    /// One round trip, in milliseconds.
    @concurrent func roundTrip() async throws -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0&measId=\(UUID().uuidString)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let start = ProcessInfo.processInfo.systemUptime
        _ = try await session.data(for: request)
        return (ProcessInfo.processInfo.systemUptime - start) * 1000
    }

    /// Sends probes one after another until the task is cancelled and returns
    /// the round trips of probes sent at or after `warmUpEnd` (before that the
    /// link is not saturated yet). A probe that times out counts as the
    /// timeout, so a badly congested link is not reported as fast.
    @concurrent func sampleUntilCancelled(warmUpEnd: TimeInterval, interval: TimeInterval) async -> [Double] {
        var samples: [Double] = []

        // The first request also opens the connection (DNS, TCP, TLS).
        _ = try? await roundTrip()

        while !Task.isCancelled {
            let sentAt = ProcessInfo.processInfo.systemUptime
            let milliseconds: Double
            do {
                milliseconds = try await roundTrip()
            } catch let error as URLError where error.code == .timedOut {
                milliseconds = timeout * 1000
            } catch {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                continue
            }
            guard !Task.isCancelled else { break }

            if sentAt >= warmUpEnd {
                samples.append(milliseconds)
            }
            let wait = interval - milliseconds / 1000
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        return samples
    }
}

// MARK: - SpeedTestManager

@MainActor
final class SpeedTestManager: ObservableObject {

    // MARK: Published properties

    @Published var state: SpeedTestState = .idle
    @Published var downloadSpeed: Double = 0
    @Published var uploadSpeed: Double = 0
    /// Smoothed speed values that animate towards the real values for better UX.
    @Published var displayDownloadSpeed: Double = 0
    @Published var displayUploadSpeed: Double = 0
    @Published var downloadProgress: Double = 0
    @Published var uploadProgress: Double = 0
    @Published var finalDownload: Double = 0
    @Published var finalUpload: Double = 0
    @Published var ping: Double = 0
    @Published var jitter: Double = 0
    /// Median latency (ms) while downloading / uploading; nil until measured.
    @Published var loadedLatencyDownload: Double?
    @Published var loadedLatencyUpload: Double?
    /// Mirrors `SpeedTestHistoryStore`, newest first.
    @Published private(set) var history: [SpeedTestResult] = []

    // MARK: Test configuration

    /// Phases are time-boxed so fast and slow connections both get a full,
    /// saturated measurement window.
    private let downloadDuration: TimeInterval = 10
    private let uploadDuration: TimeInterval = 8
    /// Initial part of each phase that is excluded from the final result,
    /// so TCP slow-start and connection setup don't drag the average down.
    private let warmUpDuration: TimeInterval = 2
    private let downloadStreamCount = 8
    private let uploadStreamCount = 6
    /// How often live speed and progress are sampled.
    private let sampleInterval: TimeInterval = 0.1
    /// Window used for the live (needle) speed value.
    private let liveWindowDuration: TimeInterval = 1.0
    /// Shortest gap between the starts of two latency probes during a phase.
    private let loadedProbeInterval: TimeInterval = 0.2
    /// Fewer probes than this are not enough for a latency-under-load value.
    private let minimumLoadedSamples = 3

    // MARK: Private properties

    private let historyStore = SpeedTestHistoryStore.shared
    private static let logger = Logger(subsystem: "com.rinetworkspeed.app", category: "SpeedTest")
    /// Connection details captured while the test runs.
    private var connectionContext: ConnectionContext?
    private var testTask: Task<Void, Never>?
    /// Monotonically increasing counter; stale catch‐blocks check this to avoid
    /// corrupting a newer test run.
    private var testGeneration: Int = 0

    /// Streams of the phase currently running — stopped on cancel / phase end.
    private var activeStreams: [TransferStream] = []

    /// Timer that smoothly interpolates display speeds towards actual measured speeds.
    private var displayTimer: Timer?
    /// Interpolation factor per tick — lower = smoother/slower animation.
    private let smoothingFactor: Double = 0.15

    // MARK: Init

    init() {
        historyStore.$results.assign(to: &$history)
    }

    // MARK: - Public API

    /// Runs a full speed test: ping → download → (2 s pause) → upload.
    func startTest() async {
        cancelTest()
        resetMetrics()

        testGeneration += 1
        let generation = testGeneration

        testTask = Task { [weak self] in
            guard let self else { return }

            // Runs alongside the test so it adds no time.
            async let context = ConnectionContext.capture()

            do {
                // ── Phase 1: Ping ──────────────────────────────────────
                self.state = .pingTesting
                let latency = try await self.measurePing()
                self.ping = latency.median
                self.jitter = latency.jitter
                try Task.checkCancellation()

                // Brief pause so the user can read the ping result.
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try Task.checkCancellation()

                // ── Phase 2: Download ──────────────────────────────────
                self.state = .downloadTesting
                let (download, downloadLatency) = try await self.runPhase(.download)
                self.loadedLatencyDownload = downloadLatency
                self.finalDownload = download
                self.downloadSpeed = download
                self.displayDownloadSpeed = download
                self.downloadProgress = 1
                try Task.checkCancellation()

                // ── Phase 3: Transition (needle → 0, 2 s pause) ───────
                self.state = .transitionToUpload
                self.downloadSpeed = 0
                try await Task.sleep(nanoseconds: 2_000_000_000)
                try Task.checkCancellation()

                // ── Phase 4: Upload ────────────────────────────────────
                self.state = .uploadTesting
                let (upload, uploadLatency) = try await self.runPhase(.upload)
                self.loadedLatencyUpload = uploadLatency
                self.finalUpload = upload
                self.uploadSpeed = upload
                self.displayUploadSpeed = upload
                self.uploadProgress = 1
                try Task.checkCancellation()

                // ── Done ───────────────────────────────────────────────
                self.connectionContext = await context
                self.stopDisplayTimer()
                self.state = .finished
                self.appendHistory()

            } catch is CancellationError {
                // Only touch shared state if we are still the active generation.
                // A newer startTest() may already be running; touching state here
                // would corrupt the new test.
                if generation == self.testGeneration {
                    self.stopActiveStreams()
                    self.stopDisplayTimer()
                    self.state = .idle
                }
            } catch {
                Self.logger.error("Speed test failed: \(error.localizedDescription, privacy: .public)")
                if generation == self.testGeneration {
                    self.stopActiveStreams()
                    self.stopDisplayTimer()
                    self.state = .failed
                }
            }
        }

        await testTask?.value
    }

    /// Cancels any in-progress test.
    func cancelTest() {
        testTask?.cancel()
        testTask = nil
        stopActiveStreams()
        stopDisplayTimer()

        if state != .finished {
            state = .idle
        }
    }

    func deleteHistory(ids: Set<UUID>) {
        historyStore.delete(ids: ids)
    }

    func clearHistory() {
        historyStore.clear()
    }

    // MARK: - Private: Reset / Cleanup

    private func resetMetrics() {
        state = .idle
        downloadSpeed = 0
        uploadSpeed = 0
        displayDownloadSpeed = 0
        displayUploadSpeed = 0
        downloadProgress = 0
        uploadProgress = 0
        finalDownload = 0
        finalUpload = 0
        ping = 0
        jitter = 0
        loadedLatencyDownload = nil
        loadedLatencyUpload = nil
        connectionContext = nil

        startDisplayTimer()
    }

    private func stopActiveStreams() {
        activeStreams.forEach { $0.stop() }
        activeStreams = []
    }

    // MARK: - Private: Ping

    /// Measures round-trip latency to the same server used for the transfer
    /// phases. The first request is discarded because it includes DNS, TCP
    /// and TLS setup; the median of the remaining samples is reported.
    /// Median round trip and jitter (mean difference between consecutive samples), in ms.
    private func measurePing() async throws -> (median: Double, jitter: Double) {
        let probe = LatencyProbe()
        defer { probe.invalidate() }

        var results: [Double] = []

        for attempt in 0..<6 {
            try Task.checkCancellation()
            let elapsed = try await probe.roundTrip()
            if attempt > 0 {
                results.append(elapsed)
            }
        }

        let sorted = results.sorted()
        guard !sorted.isEmpty else { return (0, 0) }

        let deltas = zip(results.dropFirst(), results).map { abs($0 - $1) }
        let jitter = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count)
        return (sorted[sorted.count / 2], jitter)
    }

    // MARK: - Private: Transfer Phase

    /// Runs one time-boxed transfer phase with several parallel streams.
    /// Live speed and progress are published every `sampleInterval`. Returns
    /// the average throughput after the warm-up period (bytes/second) and the
    /// median latency measured on a separate connection meanwhile (ms).
    private func runPhase(_ kind: TransferKind) async throws -> (speed: Double, loadedLatency: Double?) {
        let duration = kind == .download ? downloadDuration : uploadDuration
        let streamCount = kind == .download ? downloadStreamCount : uploadStreamCount

        let counter = ByteCounter()
        let streams = (0..<streamCount).map { _ in TransferStream(kind: kind, counter: counter) }
        activeStreams = streams
        streams.forEach { $0.start() }
        defer {
            streams.forEach { $0.stop() }
            if activeStreams.first === streams.first {
                activeStreams = []
            }
        }

        let startTime = ProcessInfo.processInfo.systemUptime

        // Latency under load: probes run on their own connection while the
        // streams saturate the link.
        let probe = LatencyProbe()
        let warmUpEnd = startTime + warmUpDuration
        let probeInterval = loadedProbeInterval
        let probeTask = Task.detached {
            await probe.sampleUntilCancelled(warmUpEnd: warmUpEnd, interval: probeInterval)
        }
        defer {
            probeTask.cancel()
            probe.invalidate()
        }

        var samples: [(time: TimeInterval, bytes: Int64)] = [(startTime, 0)]
        var warmUpBaseline: (time: TimeInterval, bytes: Int64)?

        while true {
            try await Task.sleep(nanoseconds: UInt64(sampleInterval * 1_000_000_000))

            let now = ProcessInfo.processInfo.systemUptime
            let bytes = counter.total
            let elapsed = now - startTime
            samples.append((now, bytes))

            // Every stream gave up without moving any data — nothing to measure.
            if bytes == 0 && counter.failureCount >= streamCount * 2 {
                throw URLError(.cannotConnectToHost)
            }

            // Live speed over the trailing window.
            let windowStart = now - liveWindowDuration
            // Keep the newest sample at or before the window start as the anchor.
            while samples.count > 2 && samples[1].time <= windowStart {
                samples.removeFirst()
            }
            if let first = samples.first, now - first.time > 0.05 {
                let live = Double(bytes - first.bytes) / (now - first.time)
                setLive(kind, speed: live, progress: min(1, elapsed / duration))
            }

            if warmUpBaseline == nil && elapsed >= warmUpDuration {
                warmUpBaseline = (now, bytes)
            }

            if elapsed >= duration {
                guard bytes > 0 else { throw URLError(.cannotConnectToHost) }
                let baseline = warmUpBaseline ?? (startTime, 0)
                let measuredTime = max(now - baseline.time, 0.001)
                let speed = Double(bytes - baseline.bytes) / measuredTime

                probeTask.cancel()
                let latencies = await probeTask.value
                let loadedLatency = latencies.count >= minimumLoadedSamples ? Self.median(latencies) : nil
                return (speed, loadedLatency)
            }
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private func setLive(_ kind: TransferKind, speed: Double, progress: Double) {
        switch kind {
        case .download:
            downloadSpeed = speed
            downloadProgress = progress
        case .upload:
            uploadSpeed = speed
            uploadProgress = progress
        }
    }

    // MARK: - Display interpolation timer

    /// Starts a 30-fps timer that smoothly interpolates `displayDownloadSpeed`
    /// and `displayUploadSpeed` towards the raw measured values.
    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tickDisplaySpeeds()
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    /// Each tick moves the display values a fraction closer to the real values.
    private func tickDisplaySpeeds() {
        let dlTarget: Double
        let ulTarget: Double

        switch state {
        case .downloadTesting:
            dlTarget = downloadSpeed
            ulTarget = 0
        case .transitionToUpload:
            // Keep showing final download in the live metrics row.
            // The speedometer needle is forced to zero by the view's
            // onChange(of: state) handler — not by the display speed.
            dlTarget = finalDownload
            ulTarget = 0
        case .uploadTesting:
            dlTarget = finalDownload > 0 ? finalDownload : downloadSpeed
            ulTarget = uploadSpeed
        case .finished:
            dlTarget = finalDownload
            ulTarget = finalUpload
        default:
            dlTarget = 0
            ulTarget = 0
        }

        displayDownloadSpeed += (dlTarget - displayDownloadSpeed) * smoothingFactor
        displayUploadSpeed  += (ulTarget - displayUploadSpeed)  * smoothingFactor

        // Snap to target when close enough to avoid endless tiny deltas.
        if abs(displayDownloadSpeed - dlTarget) < 100 {
            displayDownloadSpeed = dlTarget
        }
        if abs(displayUploadSpeed - ulTarget) < 100 {
            displayUploadSpeed = ulTarget
        }
    }

    // MARK: - History

    private func appendHistory() {
        let result = SpeedTestResult(
            date: Date(),
            downloadSpeed: finalDownload,
            uploadSpeed: finalUpload,
            ping: ping,
            jitter: jitter,
            connection: connectionContext?.kind,
            ssid: connectionContext?.ssid,
            isp: connectionContext?.isp,
            loadedLatencyDownload: loadedLatencyDownload,
            loadedLatencyUpload: loadedLatencyUpload,
            radioTechnology: connectionContext?.radioTechnology,
            latitude: connectionContext?.location?.latitude,
            longitude: connectionContext?.location?.longitude
        )

        // Compare Wi-Fi with Wi-Fi and cellular with cellular; a cellular test
        // is not a "drop" just because home Wi-Fi is faster.
        let comparable = history.filter { earlier in
            guard let kind = result.connection, let earlierKind = earlier.connection else { return true }
            return kind == earlierKind
        }
        NotificationManager.shared.checkSpeedDrop(
            latestDownload: result.downloadSpeed,
            previousDownloads: comparable.map(\.downloadSpeed)
        )

        historyStore.add(result)
        WidgetSharedStore.saveLastSpeedTest(result)
        ReviewPromptStore.recordSuccessfulTest()
    }
}
