import Foundation
import Observation
import StoreKit

/// What Pro unlocks. Change these to move features between free and Pro.
enum Entitlements {
    static let freePlaylistLimit = 2
    static let carModeIsPro = true
}

@MainActor @Observable
final class Purchases {
    static let productIDs = ["app.backseat.pro.weekly", "app.backseat.pro.yearly", "app.backseat.pro.lifetime"]

    private(set) var products: [Product] = []
    private(set) var isPro: Bool = UserDefaults.standard.bool(forKey: "isPro") {
        didSet { UserDefaults.standard.set(isPro, forKey: "isPro") }
    }
    private(set) var loadError: String?
    private(set) var isLoading = false

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await Product.products(for: Self.productIDs)
            products = list.sorted { Self.productIDs.firstIndex(of: $0.id)! < Self.productIDs.firstIndex(of: $1.id)! }
            loadError = list.isEmpty ? "Plans aren't available right now. Check your connection and try again." : nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, Self.productIDs.contains(t.productID), t.revocationDate == nil {
                active = true
            }
        }
        isPro = active
    }

    /// Returns true when the purchase completed.
    func purchase(_ product: Product) async throws -> Bool {
        switch try await product.purchase() {
        case .success(.verified(let t)):
            await t.finish()
            await refreshEntitlements()
            return true
        case .success(.unverified):
            throw AppError.message("The App Store could not verify this purchase.")
        case .pending:
            throw AppError.message("Your purchase is waiting for approval. Pro unlocks as soon as it's approved.")
        case .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
        if !isPro { throw AppError.message("No previous purchase was found for this Apple Account.") }
    }

    var canAddPlaylist: (Int) -> Bool {
        { [isPro] count in isPro || count < Entitlements.freePlaylistLimit }
    }
}
