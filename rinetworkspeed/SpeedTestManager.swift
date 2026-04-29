//
//  SpeedTestManager.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import Foundation
import Combine

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
    let downloadSpeed: Double
    let uploadSpeed: Double
    let ping: Double

    init(id: UUID = UUID(), date: Date, downloadSpeed: Double, uploadSpeed: Double, ping: Double) {
        self.id = id
        self.date = date
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.ping = ping
    }
}

// MARK: - Transfer Delegate

/// Dedicated URLSession delegate for a single transfer phase (download or upload).
/// Each phase creates its own delegate + session, avoiding shared‐state bugs.
/// Closures are immutable after init — no cross‐thread data races.
private final class TransferDelegate: NSObject,
                                       URLSessionDataDelegate,
                                       URLSessionTaskDelegate,
                                       @unchecked Sendable {
    let onDataReceived: ((Int64) -> Void)?
    let onBytesSent: ((Int64, Int64, Int64) -> Void)?
    let onComplete: ((Error?) -> Void)?

    init(onDataReceived: ((Int64) -> Void)? = nil,
         onBytesSent: ((Int64, Int64, Int64) -> Void)? = nil,
         onComplete: ((Error?) -> Void)? = nil) {
        self.onDataReceived = onDataReceived
        self.onBytesSent = onBytesSent
        self.onComplete = onComplete
        super.init()
    }

    // Allow download data to stream through (don't buffer the entire response).
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Reject non-2xx HTTP responses early so the test fails fast.
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onDataReceived?(Int64(data.count))
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        onBytesSent?(bytesSent, totalBytesSent, totalBytesExpectedToSend)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete?(error)
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
    @Published var history: [SpeedTestResult] = []

    // MARK: Private properties

    private let historyKey = "speedTestHistory"
    private var testTask: Task<Void, Never>?
    /// Monotonically increasing counter; stale catch‐blocks check this to avoid
    /// corrupting a newer test run.
    private var testGeneration: Int = 0

    // Active transfer resources — exactly one phase uses these at a time.
    private var activeSession: URLSession?
    private var activeDelegate: TransferDelegate?
    private var activeURLTask: URLSessionTask?
    private var activeContinuation: CheckedContinuation<Void, Error>?

    // Download metrics
    private var downloadStartDate: Date?
    private var downloadBytesReceived: Int64 = 0
    private var downloadExpectedBytes: Int64 = 100_000_000
    /// Rolling window of (timestamp, chunkBytes) for smooth speed averaging.
    private var downloadChunks: [(date: Date, bytes: Int64)] = []

    // Upload metrics
    private var uploadStartDate: Date?
    private var uploadBytesSent: Int64 = 0
    private var uploadExpectedBytes: Int64 = 50_000_000
    /// Rolling window of (timestamp, deltaBytes) for smooth speed averaging.
    private var uploadChunks: [(date: Date, bytes: Int64)] = []

    /// How many seconds the rolling‐average window covers.
    private let rollingWindowDuration: TimeInterval = 2.0

    /// Timer that smoothly interpolates display speeds towards actual measured speeds.
    private var displayTimer: Timer?
    /// Interpolation factor per tick — lower = smoother/slower animation.
    private let smoothingFactor: Double = 0.15

    // MARK: Init

    init() {
        loadHistory()
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

            do {
                // ── Phase 1: Ping ──────────────────────────────────────
                self.state = .pingTesting
                self.ping = try await self.measurePing()
                try Task.checkCancellation()

                // Probe to determine adaptive file sizes (UI still shows "ping" state).
                let estimatedBps = (try? await self.probeDownloadSpeed()) ?? 10_000_000
                self.downloadExpectedBytes = Self.adaptiveDownloadBytes(estimatedBps: estimatedBps)
                self.uploadExpectedBytes   = Self.adaptiveUploadBytes(estimatedBps: estimatedBps)
                try Task.checkCancellation()

                // Brief pause so the user can read the ping result.
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try Task.checkCancellation()

                // ── Phase 2: Download ──────────────────────────────────
                self.state = .downloadTesting
                try await self.runDownloadTest()
                try Task.checkCancellation()

                // ── Phase 3: Transition (needle → 0, 2 s pause) ───────
                self.state = .transitionToUpload
                self.downloadSpeed = 0
                try await Task.sleep(nanoseconds: 2_000_000_000)
                try Task.checkCancellation()

                // ── Phase 4: Upload ────────────────────────────────────
                self.state = .uploadTesting
                try await self.runUploadTest()
                try Task.checkCancellation()

                // ── Done ───────────────────────────────────────────────
                self.stopDisplayTimer()
                self.state = .finished
                self.appendHistory()

            } catch is CancellationError {
                // Only touch shared state if we are still the active generation.
                // A newer startTest() may already be running; touching state here
                // would corrupt the new test.
                if generation == self.testGeneration {
                    self.stopDisplayTimer()
                    self.state = .idle
                }
            } catch {
                if generation == self.testGeneration {
                    self.cleanupActiveTransfer()
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
        cleanupActiveTransfer()
        stopDisplayTimer()

        if state != .finished {
            state = .idle
        }
    }

    func deleteHistory(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            history.remove(at: index)
        }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
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

        downloadStartDate = nil
        downloadBytesReceived = 0
        downloadExpectedBytes = 100_000_000
        downloadChunks = []

        uploadStartDate = nil
        uploadBytesSent = 0
        uploadExpectedBytes = 50_000_000
        uploadChunks = []

        startDisplayTimer()
    }

    /// Tears down the active URLSession, task, and continuation.
    private func cleanupActiveTransfer() {
        activeURLTask?.cancel()
        activeURLTask = nil
        activeSession?.invalidateAndCancel()
        activeSession = nil
        activeDelegate = nil

        if let continuation = activeContinuation {
            activeContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
    }

    // MARK: - Private: Ping

    private func measurePing() async throws -> Double {
        let url = URL(string: "https://www.google.com")!
        let pingSession = URLSession(configuration: .ephemeral)
        defer { pingSession.invalidateAndCancel() }

        var results: [Double] = []

        for _ in 0..<3 {
            try Task.checkCancellation()

            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10

            let start = Date()
            _ = try await pingSession.data(for: request)
            let elapsed = Date().timeIntervalSince(start) * 1000
            results.append(elapsed)
        }

        return results.reduce(0, +) / Double(max(results.count, 1))
    }

    // MARK: - Private: Probe

    /// Downloads 1 MB to estimate line speed (bytes/second).
    private func probeDownloadSpeed() async throws -> Double {
        let probeSize: Int64 = 1_000_000
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(probeSize)") else {
            return 10_000_000
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let probeSession = URLSession(configuration: .ephemeral)
        defer { probeSession.invalidateAndCancel() }
        let start = Date()
        _ = try await probeSession.data(for: request)
        let elapsed = max(Date().timeIntervalSince(start), 0.001)
        return Double(probeSize) / elapsed
    }

    /// Target ~10 s of download. Clamped to 10 MB – 200 MB.
    private static func adaptiveDownloadBytes(estimatedBps: Double) -> Int64 {
        Int64(min(max(estimatedBps * 10.0, 10_000_000), 200_000_000))
    }

    /// Target ~8 s of upload. Clamped to 5 MB – 100 MB.
    private static func adaptiveUploadBytes(estimatedBps: Double) -> Int64 {
        Int64(min(max(estimatedBps * 0.65 * 8.0, 5_000_000), 100_000_000))
    }

    // MARK: - Private: Download Test

    private func runDownloadTest() async throws {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(downloadExpectedBytes)") else {
            throw URLError(.badURL)
        }

        // Reset download tracking
        downloadStartDate = Date()
        downloadBytesReceived = 0
        downloadChunks = []
        downloadProgress = 0
        downloadSpeed = 0

        // Create a dedicated delegate + session for this phase.
        let delegate = TransferDelegate(
            onDataReceived: { [weak self] chunkBytes in
                let now = Date()
                Task { @MainActor [weak self] in
                    self?.handleDownloadChunk(bytes: chunkBytes, date: now)
                }
            },
            onComplete: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleTransferComplete(phase: .download, error: error)
                }
            }
        )

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        activeDelegate = delegate
        activeSession = session

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.activeContinuation = continuation
            let task = session.dataTask(with: URLRequest(url: url))
            self.activeURLTask = task
            task.resume()
        }
    }

    private func handleDownloadChunk(bytes: Int64, date: Date) {
        guard state == .downloadTesting else { return }

        downloadBytesReceived += bytes
        downloadChunks.append((date: date, bytes: bytes))
        let cutoff = date.addingTimeInterval(-rollingWindowDuration)
        downloadChunks.removeAll { $0.date < cutoff }

        if let first = downloadChunks.first {
            let windowDuration = date.timeIntervalSince(first.date)
            let windowBytes = downloadChunks.reduce(Int64(0)) { $0 + $1.bytes }
            if windowDuration > 0.05 {
                downloadSpeed = Double(windowBytes) / windowDuration
            }
        }

        let expected = max(Double(downloadExpectedBytes), 1)
        downloadProgress = min(1, Double(downloadBytesReceived) / expected)
    }

    // MARK: - Private: Upload Test

    private func runUploadTest() async throws {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else {
            throw URLError(.badURL)
        }

        // Zero-filled payload avoids an expensive random-data generation loop.
        let payload = Data(count: Int(uploadExpectedBytes))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(payload.count), forHTTPHeaderField: "Content-Length")

        // Reset upload tracking
        uploadStartDate = Date()
        uploadBytesSent = 0
        uploadChunks = []
        uploadProgress = 0
        uploadSpeed = 0

        // Create a dedicated delegate + session for this phase.
        let delegate = TransferDelegate(
            onBytesSent: { [weak self] _, totalSent, totalExpected in
                let now = Date()
                Task { @MainActor [weak self] in
                    self?.handleUploadProgress(totalSent: totalSent, totalExpected: totalExpected, date: now)
                }
            },
            onComplete: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleTransferComplete(phase: .upload, error: error)
                }
            }
        )

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        activeDelegate = delegate
        activeSession = session

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.activeContinuation = continuation
            let task = session.uploadTask(with: request, from: payload)
            self.activeURLTask = task
            task.resume()
        }
    }

    private func handleUploadProgress(totalSent: Int64, totalExpected: Int64, date: Date) {
        guard state == .uploadTesting else { return }

        let delta = totalSent - uploadBytesSent
        if delta > 0 {
            uploadChunks.append((date: date, bytes: delta))
        }
        let cutoff = date.addingTimeInterval(-rollingWindowDuration)
        uploadChunks.removeAll { $0.date < cutoff }

        if let first = uploadChunks.first {
            let windowDuration = date.timeIntervalSince(first.date)
            let windowBytes = uploadChunks.reduce(Int64(0)) { $0 + $1.bytes }
            if windowDuration > 0.05 {
                uploadSpeed = Double(windowBytes) / windowDuration
            }
        }

        uploadBytesSent = totalSent
        let expected = max(Double(totalExpected > 0 ? totalExpected : uploadExpectedBytes), 1)
        uploadProgress = min(1, Double(totalSent) / expected)
    }

    // MARK: - Private: Transfer Completion

    private enum TransferPhase { case download, upload }

    private func handleTransferComplete(phase: TransferPhase, error: Error?) {
        guard let continuation = activeContinuation else { return }
        activeContinuation = nil

        // Release session resources for this phase
        activeURLTask = nil
        activeSession?.finishTasksAndInvalidate()
        activeSession = nil
        activeDelegate = nil

        if let error {
            continuation.resume(throwing: error)
            return
        }

        switch phase {
        case .download:
            let duration = max(Date().timeIntervalSince(downloadStartDate ?? Date()), 0.001)
            finalDownload = Double(downloadBytesReceived) / duration
            downloadSpeed = finalDownload
            displayDownloadSpeed = finalDownload
            downloadProgress = 1

        case .upload:
            let duration = max(Date().timeIntervalSince(uploadStartDate ?? Date()), 0.001)
            finalUpload = Double(uploadBytesSent) / duration
            uploadSpeed = finalUpload
            displayUploadSpeed = finalUpload
            uploadProgress = 1
        }

        continuation.resume()
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
            ping: ping
        )

        history.insert(result, at: 0)
        if history.count > 10 {
            history = Array(history.prefix(10))
        }
        saveHistory()
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let stored = try? JSONDecoder().decode([SpeedTestResult].self, from: data) else {
            history = []
            return
        }
        history = stored
    }
}
