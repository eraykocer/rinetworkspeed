//
//  ProFeature.swift
//  rinetworkspeed
//
//  Created by Eray Kocer on 10.04.2026.
//

import SwiftUI

// MARK: - Pro Feature Enum

enum ProFeature: String, CaseIterable {
    case widget       = "Widget & Live Activity"
    case speedTest    = "Speed Test"
    case pingMonitor  = "Ping Monitor"
    case appleWatch   = "Apple Watch"
    case notifications = "Smart Notifications"
    case history      = "History Reports"
    case dataLimit    = "Data Limit"

    var systemImage: String {
        switch self {
        case .widget:        return "square.stack.3d.up.fill"
        case .speedTest:     return "bolt.fill"
        case .pingMonitor:   return "dot.radiowaves.left.and.right"
        case .appleWatch:    return "applewatch"
        case .notifications: return "bell.badge.fill"
        case .history:       return "clock.arrow.circlepath"
        case .dataLimit:     return "externaldrive.fill.badge.wifi"
        }
    }
}

// MARK: - ProGate View Modifier

/// Intercepts interaction on a view when the user does not have a Pro entitlement
/// and automatically presents the PaywallView.
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
                }
            }
            .fullScreenCover(isPresented: $showingPaywall) {
                PaywallView()
            }
    }
}

extension View {
    /// Gate a view behind the Pro entitlement. Tapping while non-Pro shows the paywall.
    func proGated(feature: ProFeature) -> some View {
        modifier(ProGateModifier(feature: feature))
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
                            .init(color: .white.opacity(0.13), location: phase),
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
