import Foundation
import Observation
import StoreKit

/// Pro entitlement via StoreKit 2. No account: purchases belong to the
/// user's Apple Account and appear on all their devices.
@MainActor
@Observable
final class Store {
    static let subscriptionIDs = ["toolpath_pro_yearly", "toolpath_pro_monthly"]
    static let creditPackID = "toolpath_ai_100"
    static var productIDs: [String] { subscriptionIDs + [creditPackID] }

    /// Free-tier limits. Safety features are never limited.
    enum Limit {
        static let machines = 1
        static let recipes = 5
    }

    /// Subscriptions, in display order.
    private(set) var products: [Product] = []
    private(set) var creditPack: Product?
    /// Cloud assistant allowance from the Toolpath API (nil until loaded).
    private(set) var cloudQuota: ToolpathAPI.Quota?
    private(set) var isPro = false
    private(set) var isLoading = false
    var lastError: String?

    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            // Consumables the API hasn't credited yet (e.g. offline) are retried here.
            for await result in Transaction.unfinished { await handle(result) }
            await load()
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = Self.subscriptionIDs.compactMap { id in loaded.first { $0.id == id } }
            creditPack = loaded.first { $0.id == Self.creditPackID }
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result,
               Self.subscriptionIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                pro = true
                // Keep the API's record of the subscription current (renewals).
                if let quota = try? await ToolpathAPI.verify(signedTransaction: result.jwsRepresentation) { cloudQuota = quota }
            }
        }
        isPro = pro
        await refreshCloudQuota()
    }

    func refreshCloudQuota() async {
        if let quota = try? await ToolpathAPI.quota() { cloudQuota = quota }
    }

    func updateCloudQuota(_ quota: ToolpathAPI.Quota) { cloudQuota = quota }

    /// Subscriptions are finished right away (the entitlement is local);
    /// consumables only once the API has credited them, so a dropped
    /// connection can't lose a purchase.
    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result else {
            lastError = String(localized: "The purchase couldn't be verified.")
            return
        }
        do {
            cloudQuota = try await ToolpathAPI.verify(signedTransaction: result.jwsRepresentation)
            if transaction.purchaseDate > .now.addingTimeInterval(-300) {
                Telemetry.log(.purchaseCompleted, ["product": transaction.productID])
            }
            await transaction.finish()
        } catch {
            if transaction.productType != .consumable { await transaction.finish() }
            lastError = String(localized: "Your purchase is saved. Toolpath will finish setting it up when it's back online.")
        }
        await refreshEntitlements()
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase(options: [.appAccountToken(ToolpathAccount.id)])
            switch result {
            case let .success(verification):
                await handle(verification)
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }
}
