import Core
import Foundation

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// The two products (06 §11). One purchase covers both partners (decision M1).
public enum PremiumProduct: String, CaseIterable, Sendable {
    /// Auto-renewing, with a 14-day free trial as its introductory offer.
    case yearly = "premium_yearly"
    /// One-time purchase.
    case lifetime = "premium_lifetime"
}

/// A product as the store offers it right now.
public struct ProductOffer: Equatable, Sendable, Identifiable {
    public var product: PremiumProduct
    /// The store's localized price, for example "$39.99".
    public var price: String
    /// Days of free trial the store offers on this product, if any.
    public var trialDays: Int?

    public var id: PremiumProduct { product }

    public init(product: PremiumProduct, price: String, trialDays: Int? = nil) {
        self.product = product
        self.price = price
        self.trialDays = trialDays
    }
}

public enum PurchaseOutcome: Equatable, Sendable {
    case purchased
    /// The person closed the payment sheet. Not an error.
    case cancelled
    /// Waiting for approval (Ask to Buy) or a bank.
    case pending
}

public enum PurchasesError: Error, Equatable, Sendable {
    /// No RevenueCat key in this build.
    case notConfigured
    case productUnavailable
    case failed(String)
}

/// StoreKit purchases through RevenueCat. The pair's premium status is read from our backend;
/// what this service knows locally is only a fast hint for the person who paid (06 §11).
public protocol PurchasesService: Sendable {
    /// Ties purchases to our user id (RevenueCat app user ID = our user ID, 04 §3.5).
    func signIn(userID: UUID) async
    func signOut() async
    func offers() async throws -> [ProductOffer]
    func purchase(_ product: PremiumProduct) async throws -> PurchaseOutcome
    /// Restores earlier purchases. Returns whether an active entitlement was found.
    func restore() async throws -> Bool
    func hasLocalEntitlement() async -> Bool
}

/// Price wording. Every price shown anywhere says it covers both people (decision M7).
public enum PriceText {
    public static let headline = L("One price for both of you")

    /// "$39.99/year for both of you" · "$119.99 once, for both of you"
    public static func line(_ offer: ProductOffer) -> String {
        switch offer.product {
        case .yearly: L("\(offer.price)/year for both of you")
        case .lifetime: L("\(offer.price) once, for both of you")
        }
    }

    public static func title(_ product: PremiumProduct) -> String {
        switch product {
        case .yearly: L("Yearly")
        case .lifetime: L("Lifetime")
        }
    }

    /// "14 days free, then $39.99/year for both of you"
    public static func trialLine(_ offer: ProductOffer) -> String? {
        guard offer.product == .yearly, let days = offer.trialDays, days > 0 else { return nil }
        return L("\(days.formatted()) days free, then \(line(offer))")
    }

    /// The button: "Start 14 days free" when a trial applies, else "Continue".
    public static func action(_ offer: ProductOffer, trialAvailable: Bool) -> String {
        if trialAvailable, offer.product == .yearly, let days = offer.trialDays, days > 0 {
            return L("Start \(days.formatted()) days free")
        }
        return offer.product == .lifetime ? L("Get lifetime for both of you") : L("Subscribe for both of you")
    }
}

/// In-memory purchases for the Simulator demo and tests. `onPurchase` stands in for the
/// RevenueCat webhook that tells our backend about the entitlement.
public final class FakePurchasesService: PurchasesService, @unchecked Sendable {
    public enum Behavior: Sendable { case succeed, cancel, pending, fail }

    private let lock = NSLock()
    private var behavior: Behavior
    private var owned: Set<PremiumProduct> = []
    private var previouslyBought: Set<PremiumProduct>
    private var user: UUID?
    private let onPurchase: @Sendable (PremiumProduct, UUID?) -> Void
    public static let offers = [
        ProductOffer(product: .yearly, price: "$39.99", trialDays: PremiumRules.trialDays),
        ProductOffer(product: .lifetime, price: "$119.99"),
    ]

    /// - Parameter previouslyBought: purchases a "restore" will find.
    public init(
        behavior: Behavior = .succeed, previouslyBought: Set<PremiumProduct> = [],
        onPurchase: @escaping @Sendable (PremiumProduct, UUID?) -> Void = { _, _ in }
    ) {
        self.behavior = behavior
        self.previouslyBought = previouslyBought
        self.onPurchase = onPurchase
    }

    public func setBehavior(_ behavior: Behavior) { lock.withLock { self.behavior = behavior } }
    public var signedInUser: UUID? { lock.withLock { user } }

    public func signIn(userID: UUID) async { lock.withLock { user = userID } }
    public func signOut() async {
        lock.withLock {
            user = nil
            owned = []
        }
    }

    public func offers() async throws -> [ProductOffer] {
        if lock.withLock({ behavior }) == .fail { throw PurchasesError.productUnavailable }
        return Self.offers
    }

    public func purchase(_ product: PremiumProduct) async throws -> PurchaseOutcome {
        let (behavior, user) = lock.withLock { (self.behavior, self.user) }
        switch behavior {
        case .cancel: return .cancelled
        case .pending: return .pending
        case .fail: throw PurchasesError.failed("declined")
        case .succeed:
            lock.withLock { _ = owned.insert(product) }
            onPurchase(product, user)
            return .purchased
        }
    }

    public func restore() async throws -> Bool {
        let (found, user) = lock.withLock { (previouslyBought, self.user) }
        guard let product = found.first else { return false }
        lock.withLock { _ = owned.insert(product) }
        onPurchase(product, user)
        return true
    }

    public func hasLocalEntitlement() async -> Bool { lock.withLock { !owned.isEmpty } }
}
