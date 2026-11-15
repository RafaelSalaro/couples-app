import Core
import Foundation
import RevenueCat

/// RevenueCat with StoreKit 2 (06 §11). Compiles and follows RevenueCat's documented API, but
/// has not been run against App Store Connect: that needs the developer account, the two
/// products and a RevenueCat project with a "premium" entitlement.
public final class RevenueCatPurchasesService: PurchasesService, @unchecked Sendable {
    /// The entitlement both products unlock in the RevenueCat dashboard.
    public static let entitlementID = "premium"
    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    private func configureIfNeeded(userID: UUID?) {
        guard !RevenueCat.Purchases.isConfigured else { return }
        RevenueCat.Purchases.configure(withAPIKey: apiKey, appUserID: userID?.uuidString.lowercased())
    }

    public func signIn(userID: UUID) async {
        let id = userID.uuidString.lowercased()
        if RevenueCat.Purchases.isConfigured {
            guard RevenueCat.Purchases.shared.appUserID != id else { return }
            _ = try? await RevenueCat.Purchases.shared.logIn(id)
        } else {
            configureIfNeeded(userID: userID)
        }
    }

    public func signOut() async {
        guard RevenueCat.Purchases.isConfigured, !RevenueCat.Purchases.shared.isAnonymous else { return }
        _ = try? await RevenueCat.Purchases.shared.logOut()
    }

    private func storeProducts() async -> [StoreProduct] {
        configureIfNeeded(userID: nil)
        return await RevenueCat.Purchases.shared.products(PremiumProduct.allCases.map(\.rawValue))
    }

    static func trialDays(_ product: StoreProduct) -> Int? {
        guard let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial else { return nil }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }

    public func offers() async throws -> [ProductOffer] {
        let products = await storeProducts()
        let offers = PremiumProduct.allCases.compactMap { kind -> ProductOffer? in
            guard let product = products.first(where: { $0.productIdentifier == kind.rawValue }) else { return nil }
            return ProductOffer(product: kind, price: product.localizedPriceString, trialDays: Self.trialDays(product))
        }
        guard !offers.isEmpty else { throw PurchasesError.productUnavailable }
        return offers
    }

    public func purchase(_ product: PremiumProduct) async throws -> PurchaseOutcome {
        guard let storeProduct = await storeProducts().first(where: { $0.productIdentifier == product.rawValue }) else {
            throw PurchasesError.productUnavailable
        }
        do {
            let result = try await RevenueCat.Purchases.shared.purchase(product: storeProduct)
            if result.userCancelled { return .cancelled }
            return result.customerInfo.entitlements[Self.entitlementID]?.isActive == true ? .purchased : .pending
        } catch let error as RevenueCat.ErrorCode where error == .purchaseCancelledError {
            return .cancelled
        } catch let error as RevenueCat.ErrorCode where error == .paymentPendingError {
            return .pending
        } catch {
            throw PurchasesError.failed(error.localizedDescription)
        }
    }

    public func restore() async throws -> Bool {
        configureIfNeeded(userID: nil)
        do {
            let info = try await RevenueCat.Purchases.shared.restorePurchases()
            return info.entitlements[Self.entitlementID]?.isActive == true
        } catch {
            throw PurchasesError.failed(error.localizedDescription)
        }
    }

    public func hasLocalEntitlement() async -> Bool {
        guard RevenueCat.Purchases.isConfigured, let info = try? await RevenueCat.Purchases.shared.customerInfo() else { return false }
        return info.entitlements[Self.entitlementID]?.isActive == true
    }
}
