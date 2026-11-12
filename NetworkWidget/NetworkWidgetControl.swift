//
//  NetworkWidgetControl.swift
//  NetworkWidget
//
//  Control Center / Lock Screen / Action button control that opens the app
//  and starts a speed test right away (handled by AppRouter in the app).
//

import AppIntents
import SwiftUI
import WidgetKit

struct NetworkWidgetControl: ControlWidget {
    static let kind: String = "com.rinetworkspeed.NetworkWidget"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(Self.speedTestURL)) {
                Label("Speed Test", systemImage: "gauge.with.dots.needle.67percent")
            }
        }
        .displayName("Start Speed Test")
        .description("Opens RiNetwork and starts a speed test.")
    }

    private static let speedTestURL = URL(string: "rinetworkspeed://speedtest")!
}
