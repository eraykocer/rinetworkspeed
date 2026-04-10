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

    private let accentBlue  = Color(red: 0.24, green: 0.45, blue: 0.99)
    private let accentPurple = Color(red: 0.55, green: 0.28, blue: 0.96)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Selection ring
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? accentBlue : Color.white.opacity(0.18),
                            lineWidth: 2
                        )
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accentBlue, accentPurple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 12, height: 12)
                    }
                }

                // Labels
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))

                        if let badge = plan.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [accentBlue, accentPurple],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                        }
                    }
                }

                Spacer()

                // Price
                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.price)
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                    Text(plan.period)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? .white.opacity(0.6) : .white.opacity(0.3))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(red: 0.12, green: 0.14, blue: 0.28)
                            : Color.white.opacity(0.04)
                    )
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected
                            ? LinearGradient(
                                colors: [accentBlue, accentPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                colors: [.white.opacity(0.07)],
                                startPoint: .top,
                                endPoint: .bottom
                              ),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .animation(.easeInOut(duration: 0.18), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIndex: Int = 1   // default = Annual
    @State private var animateGradient: Bool = false
    @State private var isRestoring: Bool = false

    private let accentBlue   = Color(red: 0.24, green: 0.45, blue: 0.99)
    private let accentPurple = Color(red: 0.55, green: 0.28, blue: 0.96)
    private let accentOrange = Color(red: 0.99, green: 0.45, blue: 0.18)
    private let pageBackground = Color(red: 0.04, green: 0.04, blue: 0.09)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            pageBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                    contentSection
                }
            }

            // Dismiss ×
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(10)
                    .background(.white.opacity(0.11), in: Circle())
            }
            .padding(.top, 54)
            .padding(.trailing, 20)
            .zIndex(1)
        }
        .task { await purchaseManager.fetchOfferings() }
        .onChange(of: purchaseManager.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            LinearGradient(
                colors: animateGradient
                    ? [accentPurple, accentBlue, accentOrange]
                    : [accentBlue,   accentPurple, accentOrange],
                startPoint: animateGradient ? .topTrailing : .topLeading,
                endPoint:   animateGradient ? .bottomLeading : .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animateGradient)

            VStack(spacing: 18) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 6)

                VStack(spacing: 6) {
                    Text("ri Pro")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Monitor your network at full power")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 80)
            .padding(.bottom, 44)
            .padding(.horizontal, 24)
        }
        .onAppear { animateGradient = true }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(spacing: 26) {
            featuresSection
            pricingSection
            ctaButton

            if let message = purchaseManager.errorMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            footerLinks
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 48)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pro features")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            ForEach(ProFeature.allCases, id: \.rawValue) { feature in
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentBlue, accentPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text(feature.rawValue)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.05))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(spacing: 12) {
            Text("Choose a Plan")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            let plans = buildPlans()
            if purchaseManager.isLoading && plans.allSatisfy({ $0.product == nil }) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.07))
                        .frame(height: 68)
                        .shimmering()
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

    // MARK: - CTA Button

    private var ctaButton: some View {
        Button {
            Task {
                let plans = buildPlans()
                guard selectedIndex < plans.count,
                      let product = plans[selectedIndex].product else { return }
                await purchaseManager.purchase(product: product)
            }
        } label: {
            Group {
                if purchaseManager.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Get Started")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accentBlue, accentPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(purchaseManager.isLoading)
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: 14) {
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
                            .tint(.white.opacity(0.55))
                    }
                    Text("Restore Purchases")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)

            HStack(spacing: 8) {
                Link("Privacy Policy",
                     destination: URL(string: "https://rinetworkspeed.app/privacy")!)
                Text("•")
                    .foregroundStyle(.white.opacity(0.25))
                Link("Terms of Use",
                     destination: URL(string: "https://rinetworkspeed.app/terms")!)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.38))
        }
    }
}
