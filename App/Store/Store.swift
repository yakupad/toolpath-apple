import Foundation
import Observation
import StoreKit

/// Pro entitlement via StoreKit 2. No account: purchases belong to the
/// user's Apple Account and appear on all their devices.
@MainActor
@Observable
final class Store {
    static let productIDs = ["pro_yearly", "pro_monthly", "pro_lifetime"]

    /// Free-tier limits. Safety features are never limited.
    enum Limit {
        static let machines = 1
        static let recipes = 5
    }

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isLoading = false
    var lastError: String?

    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = Self.productIDs.compactMap { id in loaded.first { $0.id == id } }
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                pro = true
            }
        }
        isPro = pro
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(.verified(transaction)):
                await transaction.finish()
                await refreshEntitlements()
            case .success(.unverified):
                lastError = String(localized: "The purchase couldn't be verified.")
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
