import Core
import Foundation
import Testing
@testable import Purchases

@Suite struct PriceTextTests {
    let yearly = ProductOffer(product: .yearly, price: "$39.99", trialDays: 14)
    let lifetime = ProductOffer(product: .lifetime, price: "$119.99")

    /// Decision M7: every price shown says it covers both people.
    @Test func everyPriceSaysItCoversBoth() {
        #expect(PriceText.headline == "One price for both of you")
        #expect(PriceText.line(yearly) == "$39.99/year for both of you")
        #expect(PriceText.line(lifetime) == "$119.99 once, for both of you")
        #expect(PriceText.trialLine(yearly) == "14 days free, then $39.99/year for both of you")
        #expect(PriceText.trialLine(lifetime) == nil)
        for text in [PriceText.line(yearly), PriceText.line(lifetime), PriceText.trialLine(yearly) ?? ""] {
            #expect(text.contains("both of you"))
        }
    }

    @Test func buttonWording() {
        #expect(PriceText.action(yearly, trialAvailable: true) == "Start 14 days free")
        #expect(PriceText.action(yearly, trialAvailable: false) == "Subscribe for both of you")
        #expect(PriceText.action(lifetime, trialAvailable: true) == "Get lifetime for both of you")
        #expect(PriceText.title(.yearly) == "Yearly" && PriceText.title(.lifetime) == "Lifetime")
    }

    @Test func productIdentifiers() {
        #expect(PremiumProduct.yearly.rawValue == "premium_yearly")
        #expect(PremiumProduct.lifetime.rawValue == "premium_lifetime")
        #expect(RevenueCatPurchasesService.entitlementID == "premium")
    }
}

@Suite struct FakePurchasesServiceTests {
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    @Test func purchaseReportsToTheBackendWithOurUserID() async throws {
        let log = Log()
        let user = UUID()
        let service = FakePurchasesService { product, id in log.add("\(product.rawValue):\(id == user)") }
        await service.signIn(userID: user)
        #expect(try await service.offers().map(\.product) == [.yearly, .lifetime])
        #expect(try await service.offers().first?.trialDays == 14)
        #expect(!(await service.hasLocalEntitlement()))
        #expect(try await service.purchase(.yearly) == .purchased)
        #expect(await service.hasLocalEntitlement())
        #expect(log.all == ["premium_yearly:true"])
        await service.signOut()
        let stillOwned = await service.hasLocalEntitlement()
        #expect(!stillOwned && service.signedInUser == nil)
    }

    @Test func cancellingAndPendingAreNotErrors() async throws {
        let log = Log()
        let service = FakePurchasesService(behavior: .cancel) { product, _ in log.add(product.rawValue) }
        #expect(try await service.purchase(.lifetime) == .cancelled)
        service.setBehavior(.pending)
        #expect(try await service.purchase(.lifetime) == .pending)
        let owned = await service.hasLocalEntitlement()
        #expect(log.all.isEmpty && !owned)
        service.setBehavior(.fail)
        await #expect(throws: PurchasesError.self) { _ = try await service.purchase(.lifetime) }
        await #expect(throws: PurchasesError.productUnavailable) { _ = try await service.offers() }
    }

    @Test func restore() async throws {
        let log = Log()
        let nothing = FakePurchasesService { product, _ in log.add(product.rawValue) }
        #expect(!(try await nothing.restore()))
        let owner = FakePurchasesService(previouslyBought: [.lifetime]) { product, _ in log.add(product.rawValue) }
        #expect(try await owner.restore())
        #expect(await owner.hasLocalEntitlement())
        #expect(log.all == ["premium_lifetime"])
    }
}
