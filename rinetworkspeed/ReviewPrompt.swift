//
//  ReviewPrompt.swift
//  rinetworkspeed
//
//  Decides when to ask for an App Store rating: after a good speed test,
//  once the user has run a few, at most once per app version and with a long
//  gap between requests. iOS itself shows the prompt at most three times a year.
//

import Foundation

struct ReviewPromptPolicy {
    static let minimumSuccessfulTests = 3
    /// Only ask after a result the user is likely happy with (grade C or better).
    static let minimumScore = 55
    static let minimumDaysBetweenPrompts = 120

    var successfulTests: Int
    var lastPromptDate: Date?
    var lastPromptedVersion: String?

    func shouldPrompt(afterScore score: Int, currentVersion: String, now: Date = Date()) -> Bool {
        guard successfulTests >= Self.minimumSuccessfulTests, score >= Self.minimumScore else { return false }
        guard lastPromptedVersion != currentVersion else { return false }
        if let lastPromptDate,
           let days = Calendar.current.dateComponents([.day], from: lastPromptDate, to: now).day,
           days < Self.minimumDaysBetweenPrompts {
            return false
        }
        return true
    }
}

/// Persists the counters the policy needs.
enum ReviewPromptStore {
    private enum Key {
        static let successfulTests = "reviewSuccessfulTests"
        static let lastPromptDate = "reviewLastPromptDate"
        static let lastPromptedVersion = "reviewLastPromptedVersion"
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func recordSuccessfulTest(defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: Key.successfulTests) + 1, forKey: Key.successfulTests)
    }

    static func policy(defaults: UserDefaults = .standard) -> ReviewPromptPolicy {
        ReviewPromptPolicy(
            successfulTests: defaults.integer(forKey: Key.successfulTests),
            lastPromptDate: defaults.object(forKey: Key.lastPromptDate) as? Date,
            lastPromptedVersion: defaults.string(forKey: Key.lastPromptedVersion)
        )
    }

    static func recordPrompt(defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(now, forKey: Key.lastPromptDate)
        defaults.set(currentVersion, forKey: Key.lastPromptedVersion)
    }
}
