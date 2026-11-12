//
//  PurchaseManager.swift
//  rinetworkspeed
//
//  Created by Eray Kocer on 10.04.2026.
//

import Combine
import Foundation
import StoreKit

struct AppOfferings {
    let current: AppOffering?
}

struct AppOffering {
    let monthly: Product?
    let annual: Product?
    let lifetime: Product?
}

@MainActor
final class PurchaseManager: ObservableObject {

    #if DEBUG
    /// Debug-only escape hatch for working on gated screens without StoreKit:
    /// add `-forceProAccess YES` to the scheme's launch arguments.
    private let proAccessForced = UserDefaults.standard.bool(forKey: "forceProAccess")
    #else
    private let proAccessForced = false
    #endif

    // MARK: - Singleton
    static let shared = PurchaseManager()

    // MARK: - Published State
    @Published var isPro: Bool = false
    @Published var offerings: AppOfferings?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let productIDs = [
        "rinetworkspeed.pro.monthly",
        "rinetworkspeed.pro.yearly",
        "rinetworkspeed.pro.lifetime"
    ]

    private var transactionUpdatesTask: Task<Void, Never>?

    private init() {}

    // MARK: - Configuration
    func configure() {
        errorMessage = nil

        guard !proAccessForced else {
            isPro = true
            return
        }

        guard transactionUpdatesTask == nil else { return }

        // Purchases made outside the app (renewals, Ask to Buy, refunds,
        // another device) arrive here rather than through `purchase(product:)`.
        transactionUpdatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.checkProStatus()
            }
        }

        Task { await checkProStatus() }
    }

    // MARK: - Offerings
    func fetchOfferings() async {
        guard !proAccessForced else {
            offerings = nil
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let products = try await Product.products(for: productIDs)
            let offering = AppOffering(
                monthly: products.first(where: { $0.id == "rinetworkspeed.pro.monthly" }),
                annual: products.first(where: { $0.id == "rinetworkspeed.pro.yearly" }),
                lifetime: products.first(where: { $0.id == "rinetworkspeed.pro.lifetime" })
            )
            offerings = AppOfferings(current: offering)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Purchase
    func purchase(product: Product) async {
        guard !proAccessForced else {
            isPro = true
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await checkProStatus()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Restore
    func restorePurchases() async {
        guard !proAccessForced else {
            isPro = true
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await checkProStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pro Status
    func checkProStatus() async {
        guard !proAccessForced else {
            isPro = true
            return
        }

        var hasActivePro = false

        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(entitlement) else {
                continue
            }

            if productIDs.contains(transaction.productID) {
                hasActivePro = true
                break
            }
        }

        isPro = hasActivePro
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

private enum StoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        String(localized: "Purchase could not be verified.")
    }
}
