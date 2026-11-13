//
//  ProFeature.swift
//  rinetworkspeed
//
//  Created by Eray Kocer on 10.04.2026.
//

import SwiftUI

// MARK: - Pro Feature Enum

/// What Pro unlocks. Free: speed test, live speed, data usage, the last few
/// tests, Ping Monitor, the troubleshooter and notifications.
enum ProFeature: String, CaseIterable, Identifiable {
    case widgets
    case unlimitedHistory
    case reports
    case extendedGraph
    case networkTools
    case dataLimit

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .widgets: return "Widgets & Live Activity"
        case .unlimitedHistory: return "Unlimited Test History"
        case .reports: return "PDF & ISP Reports"
        case .extendedGraph: return "24-Hour & 7-Day Graphs"
        case .networkTools: return "Advanced Network Tools"
        case .dataLimit: return "Data Limit Alerts"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .widgets: return "Last test and data usage on the Home Screen, Lock Screen and Dynamic Island"
        case .unlimitedHistory: return "Every test with trends, filters and per-network averages"
        case .reports: return "Monthly usage report and a speed report for your provider"
        case .extendedGraph: return "Live speed history beyond the last 30 minutes"
        case .networkTools: return "IP scanner, network map, Wi-Fi survey, port scanner and more"
        case .dataLimit: return "Warnings before you reach your cellular limit"
        }
    }

    var systemImage: String {
        switch self {
        case .widgets: return "square.stack.3d.up.fill"
        case .unlimitedHistory: return "clock.arrow.circlepath"
        case .reports: return "doc.richtext.fill"
        case .extendedGraph: return "chart.xyaxis.line"
        case .networkTools: return "wrench.and.screwdriver.fill"
        case .dataLimit: return "externaldrive.fill.badge.wifi"
        }
    }
}

// MARK: - ProGate View Modifier

/// Intercepts interaction on a view when the user does not have a Pro entitlement
/// and presents the paywall with the tapped feature highlighted.
struct ProGateModifier: ViewModifier {
    let feature: ProFeature
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var showingPaywall = false

    func body(content: Content) -> some View {
        content
            .disabled(!purchaseManager.isPro)
            .overlay {
                if !purchaseManager.isPro {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showingPaywall = true }
                        .accessibilityElement()
                        .accessibilityLabel(Text(feature.title))
                        .accessibilityHint(Text("Requires Pro. Opens the upgrade screen."))
                        .accessibilityAddTraits(.isButton)
                }
            }
            .fullScreenCover(isPresented: $showingPaywall) {
                PaywallView(highlightedFeature: feature)
            }
    }
}

extension View {
    /// Gate a view behind the Pro entitlement. Tapping while non-Pro shows the paywall.
    func proGated(feature: ProFeature) -> some View {
        modifier(ProGateModifier(feature: feature))
    }
}

/// Inline placeholder shown instead of Pro content, e.g. the 24-hour graph.
struct ProLockedCard: View {
    let feature: ProFeature
    @State private var showingPaywall = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .appFont(size: 24, weight: .semibold)
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text(feature.title)
                .appFont(size: 17, weight: .bold, design: .rounded)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
            Text(feature.subtitle)
                .appFont(size: 13, weight: .regular, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                showingPaywall = true
            } label: {
                Label("Unlock with Pro", systemImage: "crown.fill")
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .appCard(padding: nil)
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView(highlightedFeature: feature)
        }
    }
}

/// Small "PRO" tag for rows that lead to a locked feature.
struct ProBadge: View {
    var body: some View {
        Text(verbatim: "PRO")
            .appFont(size: 10, weight: .heavy, design: .rounded)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppTheme.accent, in: Capsule())
            .accessibilityLabel(Text("Requires Pro"))
    }
}

// MARK: - Shimmer Modifier (used by PaywallView skeleton cards)

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.3

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: phase - 0.2),
                            .init(color: AppTheme.ink.opacity(0.13), location: phase),
                            .init(color: .clear, location: phase + 0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
