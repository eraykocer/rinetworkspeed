//
//  SpeedHistoryArchive.swift
//  rinetworkspeed
//
//  Keeps live speed beyond the 30 minutes held in memory: samples are
//  summarised per minute (average and peak) and appended to one CSV file per
//  day in Application Support. Files older than `retentionDays` are deleted.
//
//  iOS does not let the app sample in the background, so the archive only
//  covers the time the app was open; gaps are expected and shown as gaps.
//

import Foundation

struct SpeedMinuteBucket: Identifiable {
    let start: Date
    /// Bytes per second.
    let averageDownload: Double
    let averageUpload: Double
    let peakDownload: Double
    let peakUpload: Double

    var id: Date { start }
}

@MainActor
final class SpeedHistoryArchive {
    static let shared = SpeedHistoryArchive()
    static let retentionDays = 7

    private let directory: URL
    private let calendar = Calendar.current

    // Minute currently being accumulated.
    private var currentMinute: Date?
    private var downloadSum = 0.0
    private var uploadSum = 0.0
    private var downloadPeak = 0.0
    private var uploadPeak = 0.0
    private var sampleCount = 0

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeedHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pruneOldFiles()
    }

    // MARK: Recording

    func record(download: Double, upload: Double, at date: Date) {
        let minute = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        if let currentMinute, currentMinute != minute {
            flush()
        }
        currentMinute = minute
        downloadSum += download
        uploadSum += upload
        downloadPeak = max(downloadPeak, download)
        uploadPeak = max(uploadPeak, upload)
        sampleCount += 1
    }

    /// Writes the minute in progress. Called when sampling pauses; if sampling
    /// resumes within the same minute, the reader merges the two rows.
    func flush() {
        guard let bucket = pendingBucket else { return }
        append(bucket)
        currentMinute = nil
        downloadSum = 0
        uploadSum = 0
        downloadPeak = 0
        uploadPeak = 0
        sampleCount = 0
    }

    private var pendingBucket: SpeedMinuteBucket? {
        guard let currentMinute, sampleCount > 0 else { return nil }
        return SpeedMinuteBucket(
            start: currentMinute,
            averageDownload: downloadSum / Double(sampleCount),
            averageUpload: uploadSum / Double(sampleCount),
            peakDownload: downloadPeak,
            peakUpload: uploadPeak
        )
    }

    // MARK: Reading

    /// Minute buckets at or after `date`, oldest first, including the minute in progress.
    func buckets(since date: Date) -> [SpeedMinuteBucket] {
        var byMinute: [Date: SpeedMinuteBucket] = [:]
        var day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())

        while day <= today {
            for bucket in readFile(for: day) where bucket.start >= date {
                byMinute[bucket.start] = byMinute[bucket.start].map { merge($0, bucket) } ?? bucket
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        if let pending = pendingBucket, pending.start >= date {
            byMinute[pending.start] = byMinute[pending.start].map { merge($0, pending) } ?? pending
        }

        return byMinute.values.sorted { $0.start < $1.start }
    }

    private func merge(_ a: SpeedMinuteBucket, _ b: SpeedMinuteBucket) -> SpeedMinuteBucket {
        SpeedMinuteBucket(
            start: a.start,
            averageDownload: (a.averageDownload + b.averageDownload) / 2,
            averageUpload: (a.averageUpload + b.averageUpload) / 2,
            peakDownload: max(a.peakDownload, b.peakDownload),
            peakUpload: max(a.peakUpload, b.peakUpload)
        )
    }

    // MARK: Files

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func fileURL(for day: Date) -> URL {
        directory.appendingPathComponent("\(Self.dayFormatter.string(from: day)).csv")
    }

    /// One line per minute: epoch seconds, average down, average up, peak down, peak up.
    private func append(_ bucket: SpeedMinuteBucket) {
        let line = String(
            format: "%.0f,%.0f,%.0f,%.0f,%.0f\n",
            bucket.start.timeIntervalSince1970,
            bucket.averageDownload,
            bucket.averageUpload,
            bucket.peakDownload,
            bucket.peakUpload
        )
        let url = fileURL(for: bucket.start)
        let data = Data(line.utf8)

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func readFile(for day: Date) -> [SpeedMinuteBucket] {
        guard let text = try? String(contentsOf: fileURL(for: day), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: ",").compactMap { Double($0) }
            guard fields.count == 5 else { return nil }
            return SpeedMinuteBucket(
                start: Date(timeIntervalSince1970: fields[0]),
                averageDownload: fields[1],
                averageUpload: fields[2],
                peakDownload: fields[3],
                peakUpload: fields[4]
            )
        }
    }

    private func pruneOldFiles() {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: calendar.startOfDay(for: Date())),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.pathExtension == "csv" {
            guard let day = Self.dayFormatter.date(from: file.deletingPathExtension().lastPathComponent),
                  day < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
