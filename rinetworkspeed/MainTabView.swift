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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
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
                    UsageTabScreen(monitor: dataUsageMonitor, speedTestManager: speedTestManager)
                }

                Tab("Tools", systemImage: "wrench.and.screwdriver.fill", value: 3) {
                    NetworkToolsView()
                }

                Tab("Settings", systemImage: "gearshape.fill", value: 4) {
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
        .fullScreenCover(
            isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { _ in }
            )
        ) {
            OnboardingView()
        }
        .onAppear {
            monitor.start()
            dataUsageMonitor.start()
            // Only request notification permission after onboarding;
            // during first launch the onboarding page 4 handles it.
            if hasCompletedOnboarding {
                notificationManager.requestPermission()
            }
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
                monitor.applyLiveActivitySetting()
                dataUsageMonitor.start()
                if hasCompletedOnboarding {
                    notificationManager.requestPermission()
                }
                Task {
                    await notificationManager.refreshAuthorizationStatus()
                }
            } else if newPhase == .background {
                monitor.stopSampling()
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
    @ObservedObject var speedTestManager: SpeedTestManager

    var body: some View {
        UsageView(dataUsage: monitor, speedTestManager: speedTestManager)
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
