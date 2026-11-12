//
//  SpeedTestHistoryStore.swift
//  rinetworkspeed
//
//  Persists every speed test result to a JSON file in Application Support.
//  It is shared by all SpeedTestManager instances (the app UI and the
//  Siri / Shortcuts intent), so a test run from Shortcuts shows up in the app.
//

import Foundation
import Combine

@MainActor
final class SpeedTestHistoryStore: ObservableObject {
    static let shared = SpeedTestHistoryStore()

    /// Newest first.
    @Published private(set) var results: [SpeedTestResult] = []

    private let fileURL: URL
    /// History was kept in UserDefaults (capped at 10) before the file store.
    private let legacyDefaultsKey = "speedTestHistory"

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("speed-test-history.json")
        load()
    }

    func add(_ result: SpeedTestResult) {
        results.insert(result, at: 0)
        save()
    }

    func delete(ids: Set<UUID>) {
        results.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        results.removeAll()
        save()
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? Self.decoder.decode([SpeedTestResult].self, from: data) {
            results = stored
            return
        }

        if let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let legacy = try? Self.decoder.decode([SpeedTestResult].self, from: data) {
            results = legacy
            save()
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        }
    }

    private func save() {
        guard let data = try? Self.encoder.encode(results) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    // Default date strategies, matching what the UserDefaults history used.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
