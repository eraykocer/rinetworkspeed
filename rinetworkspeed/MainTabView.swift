//
//  MainTabView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var monitor = NetworkStatsMonitor()
    @StateObject private var dataUsageMonitor = DataUsageMonitor()
    @StateObject private var speedTestManager = SpeedTestManager()
    @StateObject private var pingMonitor = PingMonitor()
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var selectedTab: Int = 0
    @State private var isShowingSplash = true
    @State private var didStartSplashSequence = false
    @AppStorage("appTheme") private var appTheme: String = "system"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.07, green: 0.08, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: "house.fill", value: 0) {
                    ContentView(
                        monitor: monitor,
                        dataUsage: dataUsageMonitor,
                        speedTestManager: speedTestManager,
                        pingMonitor: pingMonitor,
                        selectedTab: $selectedTab
                    )
                }

                Tab("Graph", systemImage: "chart.xyaxis.line", value: 1) {
                    GraphView(monitor: monitor)
                }

                Tab("Usage", systemImage: "arrow.up.arrow.down.circle.fill", value: 2) {
                    UsageTabScreen(monitor: dataUsageMonitor)
                }

                Tab("Settings", systemImage: "gearshape.fill", value: 3) {
                    SettingsView(monitor: monitor)
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabBarMinimizeBehavior(.onScrollDown)
            .toolbarBackground(.visible, for: .tabBar)
            .modifier(TabBarMaterialModifier())
            .animation(.smooth(duration: 0.28), value: selectedTab)

            if isShowingSplash {
                SplashScreenView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(1)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .onAppear {
            monitor.start()
            dataUsageMonitor.start()
            notificationManager.requestPermission()
        }
        .task {
            guard !didStartSplashSequence else { return }
            didStartSplashSequence = true

            try? await Task.sleep(nanoseconds: 1_700_000_000)

            withAnimation(.easeInOut(duration: 0.45)) {
                isShowingSplash = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                monitor.start()
                dataUsageMonitor.start()
                Task {
                    await notificationManager.refreshAuthorizationStatus()
                }
            } else if newPhase == .background {
                dataUsageMonitor.stop()
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appTheme {
        case "dark":
            return .dark
        case "light":
            return .light
        default:
            return nil
        }
    }
}

private struct UsageTabScreen: View {
    @ObservedObject var monitor: DataUsageMonitor

    var body: some View {
        UsageView(dataUsage: monitor)
    }
}

private struct TabBarMaterialModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .toolbarBackground(.clear, for: .tabBar)
        } else {
            content
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        }
    }
}

#Preview {
    MainTabView()
}
