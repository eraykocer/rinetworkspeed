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
    case downloadTesting
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

@MainActor
final class SpeedTestManager: NSObject, ObservableObject {
    @Published var state: SpeedTestState = .idle
    @Published var downloadSpeed: Double = 0
    @Published var uploadSpeed: Double = 0
    @Published var downloadProgress: Double = 0
    @Published var uploadProgress: Double = 0
    @Published var finalDownload: Double = 0
    @Published var finalUpload: Double = 0
    @Published var ping: Double = 0
    @Published var history: [SpeedTestResult] = []

    private let historyKey = "speedTestHistory"
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private var activeTask: URLSessionTask?
    private var testTask: Task<Void, Never>?

    private var downloadContinuation: CheckedContinuation<Void, Error>?
    private var uploadContinuation: CheckedContinuation<Void, Error>?

    private var downloadStartDate: Date?
    private var downloadLastChunkDate: Date?
    private var downloadBytesReceived: Int64 = 0
    private var downloadExpectedBytes: Int64 = 250_000_000

    private var uploadStartDate: Date?
    private var uploadLastCallbackDate: Date?
    private var uploadBytesSent: Int64 = 0
    private var uploadExpectedBytes: Int64 = 50_000_000

    override init() {
        super.init()
        loadHistory()
    }

    func startTest() async {
        cancelTest()
        resetMetrics()

        testTask = Task { [weak self] in
            guard let self else { return }

            do {
                self.ping = try await self.measurePing()
                try Task.checkCancellation()

                self.state = .downloadTesting
                try await self.runDownloadTest()
                try Task.checkCancellation()

                self.state = .uploadTesting
                try await self.runUploadTest()
                try Task.checkCancellation()

                self.state = .finished
                self.appendHistory()
            } catch is CancellationError {
                self.state = .idle
            } catch {
                self.state = .failed
            }
        }

        await testTask?.value
    }

    func cancelTest() {
        testTask?.cancel()
        testTask = nil
        activeTask?.cancel()
        activeTask = nil

        if let downloadContinuation {
            self.downloadContinuation = nil
            downloadContinuation.resume(throwing: CancellationError())
        }

        if let uploadContinuation {
            self.uploadContinuation = nil
            uploadContinuation.resume(throwing: CancellationError())
        }

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

    private func resetMetrics() {
        state = .idle
        downloadSpeed = 0
        uploadSpeed = 0
        downloadProgress = 0
        uploadProgress = 0
        finalDownload = 0
        finalUpload = 0
        ping = 0

        downloadStartDate = nil
        downloadLastChunkDate = nil
        downloadBytesReceived = 0
        downloadExpectedBytes = 250_000_000

        uploadStartDate = nil
        uploadLastCallbackDate = nil
        uploadBytesSent = 0
        uploadExpectedBytes = 50_000_000
    }

    private func measurePing() async throws -> Double {
        let url = URL(string: "https://www.google.com")!
        let pingSession = URLSession(configuration: .ephemeral)
        var results: [Double] = []

        for _ in 0..<5 {
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

    private func runDownloadTest() async throws {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=250000000")!
        let request = URLRequest(url: url)

        downloadStartDate = Date()
        downloadLastChunkDate = downloadStartDate
        downloadBytesReceived = 0
        downloadExpectedBytes = 250_000_000
        downloadProgress = 0
        downloadSpeed = 0

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.downloadContinuation = continuation
            let task = self.session.dataTask(with: request)
            self.activeTask = task
            task.resume()
        }
    }

    private func runUploadTest() async throws {
        let url = URL(string: "https://speed.cloudflare.com/__up")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let payload = randomData(length: Int(uploadExpectedBytes))
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(payload.count), forHTTPHeaderField: "Content-Length")

        uploadStartDate = Date()
        uploadLastCallbackDate = uploadStartDate
        uploadBytesSent = 0
        uploadProgress = 0
        uploadSpeed = 0

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.uploadContinuation = continuation
            let task = self.session.uploadTask(with: request, from: payload)
            self.activeTask = task
            task.resume()
        }
    }

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

    private func randomData(length: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max)
        }
        return Data(bytes)
    }
}

extension SpeedTestManager: URLSessionDataDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.allow)
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor [weak self] in
            guard let self, dataTask == self.activeTask, self.state == .downloadTesting else { return }

            let now = Date()
            let bytes = Int64(data.count)
            self.downloadBytesReceived += bytes

            if let lastDate = self.downloadLastChunkDate {
                let delta = now.timeIntervalSince(lastDate)
                if delta > 0 {
                    self.downloadSpeed = Double(bytes) / delta
                }
            }

            self.downloadLastChunkDate = now

            let expected = max(Double(self.downloadExpectedBytes), 1)
            self.downloadProgress = min(1, Double(self.downloadBytesReceived) / expected)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        Task { @MainActor [weak self] in
            guard let self, task == self.activeTask, self.state == .uploadTesting else { return }

            let now = Date()

            if let lastDate = self.uploadLastCallbackDate {
                let delta = now.timeIntervalSince(lastDate)
                let sentDelta = totalBytesSent - self.uploadBytesSent
                if delta > 0, sentDelta > 0 {
                    self.uploadSpeed = Double(sentDelta) / delta
                }
            }

            self.uploadLastCallbackDate = now
            self.uploadBytesSent = totalBytesSent

            let expected = max(Double(totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : self.uploadExpectedBytes), 1)
            self.uploadProgress = min(1, Double(totalBytesSent) / expected)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, task == self.activeTask else { return }

            defer {
                self.activeTask = nil
            }

            if let error {
                if let downloadContinuation = self.downloadContinuation {
                    self.downloadContinuation = nil
                    downloadContinuation.resume(throwing: error)
                    return
                }

                if let uploadContinuation = self.uploadContinuation {
                    self.uploadContinuation = nil
                    uploadContinuation.resume(throwing: error)
                }
                return
            }

            if self.state == .downloadTesting {
                let duration = max(Date().timeIntervalSince(self.downloadStartDate ?? Date()), 0.001)
                self.finalDownload = Double(self.downloadBytesReceived) / duration
                self.downloadSpeed = self.finalDownload
                self.downloadProgress = 1

                if let downloadContinuation = self.downloadContinuation {
                    self.downloadContinuation = nil
                    downloadContinuation.resume()
                }
            } else if self.state == .uploadTesting {
                let duration = max(Date().timeIntervalSince(self.uploadStartDate ?? Date()), 0.001)
                self.finalUpload = Double(self.uploadBytesSent) / duration
                self.uploadSpeed = self.finalUpload
                self.uploadProgress = 1

                if let uploadContinuation = self.uploadContinuation {
                    self.uploadContinuation = nil
                    uploadContinuation.resume()
                }
            }
        }
    }
}
