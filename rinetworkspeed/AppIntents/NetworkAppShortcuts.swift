//
//  NetworkAppShortcuts.swift
//  rinetworkspeed
//
//  Registers all app shortcuts with Siri and the Shortcuts app.
//  Phrases are donated automatically when the app is launched; no user
//  action is required to enable them.
//
//  NOTE: Every phrase MUST contain \(.applicationName) — this is enforced
//  by the AppIntents framework at compile time.
//

import AppIntents

struct NetworkAppShortcuts: AppShortcutsProvider {

    static var shortcutTileColor: ShortcutTileColor = .blue

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {

        // ── Internet speed ─────────────────────────────────────────────
        AppShortcut(
            intent: GetNetworkSpeedIntent(),
            phrases: [
                "Show my speed with \(.applicationName)",
                "What is my internet speed \(.applicationName)",
                "\(.applicationName) speed"
            ],
            shortTitle: "Show Speed",
            systemImageName: "wifi"
        )

        // ── Data usage ─────────────────────────────────────────────────
        AppShortcut(
            intent: GetDataUsageIntent(),
            phrases: [
                "How much data did I use today with \(.applicationName)",
                "\(.applicationName) data usage",
                "Show my data usage \(.applicationName)"
            ],
            shortTitle: "Data Usage",
            systemImageName: "chart.bar.fill"
        )

        // ── Speed test ─────────────────────────────────────────────────
        AppShortcut(
            intent: RunSpeedTestIntent(),
            phrases: [
                "Run a speed test with \(.applicationName)",
                "\(.applicationName) speed test",
                "Test my internet speed \(.applicationName)"
            ],
            shortTitle: "Speed Test",
            systemImageName: "gauge.high"
        )

        // ── Ping ───────────────────────────────────────────────────────
        AppShortcut(
            intent: GetPingIntent(),
            phrases: [
                "What is my ping with \(.applicationName)",
                "\(.applicationName) measure ping",
                "My connection latency \(.applicationName)"
            ],
            shortTitle: "Measure Ping",
            systemImageName: "network"
        )
    }
}
