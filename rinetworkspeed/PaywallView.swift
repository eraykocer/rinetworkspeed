//
//  PaywallView.swift
//  rinetworkspeed
//
//  Created by Eray Kocer on 10.04.2026.
//

import StoreKit
import SwiftUI

// MARK: - Pricing Plan Model

struct PricingPlan {
    let title: String
    let badge: String?
    let price: String
    let period: String
    let product: Product?
}

// MARK: - Pricing Card

struct PricingCard: View {
    let plan: PricingPlan
    let isSelected: Bool
    let onTap: () -> Void

    private let gradient = AppTheme.heroGradient

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 2)
                    if isSelected {
                        Circle()
                            .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 24, height: 24)

                // Labels
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(plan.title))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? AppTheme.primaryText : .white.opacity(0.7))

                        if let badge = plan.badge {
                            Text(LocalizedStringKey(badge))
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .textCase(.uppercase)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                                )
                        }
                    }

                    Text(LocalizedStringKey(plan.period))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? AppTheme.secondaryText : AppTheme.tertiaryText)
                }

                Spacer(minLength: 8)

                // Price
                Text(plan.price)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AppTheme.primaryText : .white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .fill(isSelected ? AppTheme.accent.opacity(0.16) : AppTheme.cardFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [AppTheme.cardStroke], startPoint: .top, endPoint: .bottom),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .animation(.easeInOut(duration: 0.18), value: isSelected)
        }
        .buttonStyle(AppPressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIndex: Int = 1   // default = Annual
    @State private var animateGradient: Bool = false
    @State private var isRestoring: Bool = false

    private static let privacyURL = URL(string: "https://rinetworkspeed.app/privacy")
    private static let termsURL = URL(string: "https://rinetworkspeed.app/terms")

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    heroSection
                    featuresSection
                    pricingSection
                    ctaSection
                    footerLinks
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 52)
                .padding(.bottom, 40)
            }

            // Dismiss ×
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.1), in: Circle())
                    .overlay(Circle().stroke(AppTheme.cardStroke, lineWidth: 1))
            }
            .buttonStyle(AppPressableButtonStyle())
            .accessibilityLabel("Close")
            .padding(.top, 8)
            .padding(.trailing, AppTheme.pagePadding)
            .zIndex(1)
        }
        .appPageBackground()
        .task { await purchaseManager.fetchOfferings() }
        .onChange(of: purchaseManager.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ri Pro")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Monitor your network at full power")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 12)

                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            // Quick glance at what's included
            HStack(spacing: 0) {
                ForEach(Array(ProFeature.allCases.prefix(4).enumerated()), id: \.element.rawValue) { index, feature in
                    if index > 0 {
                        AppMetricDivider()
                    }
                    Image(systemName: feature.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 14)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: animateGradient
                    ? [AppTheme.accent, AppTheme.download, AppTheme.upload]
                    : [AppTheme.download, AppTheme.accent, AppTheme.upload.opacity(0.9)],
                startPoint: animateGradient ? .topTrailing : .topLeading,
                endPoint: animateGradient ? .bottomLeading : .bottomTrailing
            )
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animateGradient)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .shadow(color: AppTheme.accent.opacity(0.35), radius: 16, x: 0, y: 8)
        .onAppear { animateGradient = true }
    }

    // MARK: - Features

    private var featuresSection: some View {
        AppSection("Pro features") {
            let features = ProFeature.allCases
            ForEach(features, id: \.rawValue) { feature in
                AppRow(icon: feature.systemImage, tint: feature.paywallTint, title: LocalizedStringKey(feature.rawValue)) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.ping)
                }

                if feature != features.last {
                    AppRowDivider()
                }
            }
        }
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("Choose a Plan")

            let plans = buildPlans()
            if purchaseManager.isLoading && plans.allSatisfy({ $0.product == nil }) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                        .fill(AppTheme.cardFill)
                        .frame(height: 76)
                        .shimmering()
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                }
            } else {
                ForEach(Array(plans.enumerated()), id: \.offset) { idx, plan in
                    PricingCard(plan: plan, isSelected: selectedIndex == idx) {
                        selectedIndex = idx
                    }
                }
            }
        }
    }

    private func buildPlans() -> [PricingPlan] {
        let offering = purchaseManager.offerings?.current
        return [
            PricingPlan(
                title:   "Monthly",
                badge:   nil,
                price:   offering?.monthly?.displayPrice ?? "₺49,99",
                period:  "/ month",
                product: offering?.monthly
            ),
            PricingPlan(
                title:   "Annual",
                badge:   "Most Popular",
                price:   offering?.annual?.displayPrice ?? "₺299,99",
                period:  "/ year",
                product: offering?.annual
            ),
            PricingPlan(
                title:   "Lifetime",
                badge:   nil,
                price:   offering?.lifetime?.displayPrice ?? "₺599,99",
                period:  "Forever",
                product: offering?.lifetime
            )
        ]
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    let plans = buildPlans()
                    guard selectedIndex < plans.count,
                          let product = plans[selectedIndex].product else { return }
                    await purchaseManager.purchase(product: product)
                }
            } label: {
                ZStack {
                    // Keeps the button height stable while loading
                    Text("Get Started")
                        .opacity(purchaseManager.isLoading ? 0 : 1)
                    if purchaseManager.isLoading {
                        ProgressView().tint(.white)
                    }
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .padding(.vertical, 2)
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(purchaseManager.isLoading)
            .shadow(color: AppTheme.accent.opacity(0.35), radius: 12, x: 0, y: 6)

            if let message = purchaseManager.errorMessage {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    isRestoring = true
                    await purchaseManager.restorePurchases()
                    isRestoring = false
                }
            } label: {
                HStack(spacing: 6) {
                    if isRestoring {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(AppTheme.secondaryText)
                    }
                    Text("Restore Purchases")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)

            HStack(spacing: 8) {
                if let privacyURL = Self.privacyURL {
                    Link("Privacy Policy", destination: privacyURL)
                }
                Text("•")
                    .foregroundStyle(.white.opacity(0.2))
                if let termsURL = Self.termsURL {
                    Link("Terms of Use", destination: termsURL)
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.tertiaryText)
            .tint(AppTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Feature Tints

private extension ProFeature {
    var paywallTint: Color {
        switch self {
        case .widget:        return AppTheme.accent
        case .speedTest:     return AppTheme.download
        case .pingMonitor:   return AppTheme.ping
        case .appleWatch:    return Color(red: 0.84, green: 0.28, blue: 0.74)
        case .notifications: return AppTheme.danger
        case .history:       return Color(red: 0.20, green: 0.75, blue: 0.99)
        case .dataLimit:     return AppTheme.upload
        }
    }
}

#Preview {
    PaywallView()
        .preferredColorScheme(.dark)
}
