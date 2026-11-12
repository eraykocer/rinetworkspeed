//
//  MainTabView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Combine

struct MainTabView: View {
    // Held with @State (not @StateObject) so the root view does NOT subscribe to
    // their high-frequency changes. Re-rendering the whole TabView on every
    // monitor tick caused stutter when switching tabs; each tab observes only
    // the managers it actually displays.
    @State private var monitor = NetworkStatsMonitor()
    @State private var dataUsageMonitor = DataUsageMonitor()
    @State private var speedTestManager = SpeedTestManager()
    @State private var pingMonitor = PingMonitor()
    private let notificationManager = NotificationManager.shared
    private let router = AppRouter.shared
    @State private var selectedTab: Int = 0
    /// Set when a widget, control, deep link or notification asks to run a speed test.
    @State private var speedTestRequested = false
    @State private var isShowingSplash = true
    @State private var didStartSplashSequence = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: "house.fill", value: 0) {
                    ContentView(
                        monitor: monitor,
                        dataUsage: dataUsageMonitor,
                        speedTestManager: speedTestManager,
                        pingMonitor: pingMonitor,
                        selectedTab: $selectedTab,
                        speedTestRequested: $speedTestRequested
                    )
                }

                Tab("Graph", systemImage: "chart.xyaxis.line", value: 1) {
                    GraphView(monitor: monitor)
                }

                Tab("Usage", systemImage: "arrow.up.arrow.down.circle.fill", value: 2) {
                    UsageTabScreen(monitor: dataUsageMonitor, speedTestManager: speedTestManager)
                }

                Tab("Tools", systemImage: "wrench.and.screwdriver.fill", value: 3) {
                    NetworkToolsView(speedTestManager: speedTestManager)
                }

                Tab("Settings", systemImage: "gearshape.fill", value: 4) {
                    SettingsView(monitor: monitor)
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .toolbarBackground(.visible, for: .tabBar)
            .modifier(TabBarMaterialModifier())
            // Lighter violet than AppTheme.accent so the selected tab stays readable on the dark bar.
            .tint(Color(red: 0.62, green: 0.52, blue: 1.0))

            if isShowingSplash {
                SplashScreenView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(1)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .fullScreenCover(
            isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { _ in }
            )
        ) {
            OnboardingView()
        }
        .onOpenURL { url in
            router.handle(url: url)
        }
        .onReceive(router.$pendingDestination.compactMap { $0 }) { destination in
            router.pendingDestination = nil
            selectedTab = destination.tab
            if destination == .speedTest {
                speedTestRequested = true
            }
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
                monitor.resumeFromBackground()
                dataUsageMonitor.start()
                if hasCompletedOnboarding {
                    notificationManager.requestPermission()
                }
                Task {
                    await notificationManager.refreshAuthorizationStatus()
                }
            } else if newPhase == .background {
                monitor.prepareForBackground()
                dataUsageMonitor.stop()
                // Let widgets pick up the latest usage counters.
                WidgetSharedStore.reloadWidgets()
            }
        }
    }
}

private struct UsageTabScreen: View {
    @ObservedObject var monitor: DataUsageMonitor
    let speedTestManager: SpeedTestManager

    var body: some View {
        UsageView(dataUsage: monitor, speedTestManager: speedTestManager)
    }
}

private struct TabBarMaterialModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
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
