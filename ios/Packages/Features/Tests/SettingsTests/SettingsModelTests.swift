import Backend
import Core
import FeatureSupport
import FeatureTestSupport
import Foundation
import Purchases
import Testing
@testable import SettingsFeature

@MainActor @Suite struct SettingsModelTests {
    @Test func profileName() async {
        let app = await TestApp()
        let model = SettingsModel(app: app.model)
        #expect(model.name == "Rafa" && !model.canSaveName)
        model.name = "  "
        #expect(!model.canSaveName)
        model.name = " Rafael "
        #expect(model.canSaveName)
        await model.saveName()
        #expect(app.model.myName == "Rafael" && app.store.load().myName == "Rafael")
    }

    @Test func dailyMaximumStaysInRange() async {
        let app = await TestApp()
        let model = SettingsModel(app: app.model)
        await model.setDailyMax(120)
        #expect(model.dailyMax == 120 && app.model.myMinutes?.dailyMax == 120)
        await model.setDailyMax(300)
        await model.setDailyMax(0)
        #expect(model.dailyMax == 120)
    }

    /// Feature spec §11: every category can be muted except unlock requests and schedule requests.
    @Test func notificationCategories() async {
        let app = await TestApp()
        let model = SettingsModel(app: app.model)
        #expect(NotificationKind.allCases.allSatisfy { model.isOn($0) })
        await model.setOn(false, for: .kudos)
        await model.setOn(false, for: .unlockRequest)
        await model.setOn(false, for: .scheduleRequest)
        #expect(!model.isOn(.kudos) && model.isOn(.unlockRequest) && model.isOn(.scheduleRequest))
        await model.setOn(true, for: .kudos)
        #expect(model.isOn(.kudos))
        #expect(Set(NotificationKind.allCases.map(SettingsModel.title)).count == NotificationKind.allCases.count)
    }

    /// Decision P24: the weekly report email is off by default and opt-in.
    @Test func weeklyReportEmailIsOptIn() async throws {
        let app = await TestApp()
        let model = SettingsModel(app: app.model)
        #expect(!model.weeklyReportEmail)
        await model.setWeeklyReportEmail(true)
        #expect(model.weeklyReportEmail)
        #expect(try await app.backend.fetchSettings().notificationPrefs.weeklyReportEmail)
    }

    @Test func subscriptionLine() async {
        let app = await TestApp()
        let model = SettingsModel(app: app.model)
        #expect(model.subscriptionLine == "Free. Premium is one price for both of you.")
        app.world.setEntitlement(.subscription, for: TestApp.partnerID)
        await app.settle()
        #expect(model.subscriptionLine == "Premium for both of you. Paid by Ana.")
        app.world.setEntitlement(.lifetime, for: TestApp.partnerID)
        await app.settle()
        #expect(model.subscriptionLine == "Premium for both of you, for good. Thanks to Ana.")
    }

    @Test func exportWritesAJSONFile() async throws {
        let app = await TestApp()
        let model = SettingsModel(app: app.model)
        await model.export()
        let url = try #require(model.exportURL)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(json["email"] as? String == "rafa@example.com")
        try? FileManager.default.removeItem(at: url)
    }

    /// Feature spec §14, verified against the backend: the account is gone and the partner is unpaired.
    @Test func accountDeletion() async throws {
        let app = await TestApp()
        let model = SettingsModel(app: app.model)
        #expect(model.deletionPoints.first == "You and Ana are unpaired right away.")
        #expect(model.deletionPoints.last?.contains("does not cancel an Apple subscription") == true)
        await model.deleteAccount()
        #expect(app.world.deletedUsers == [TestApp.me] && !app.world.hasPerson(TestApp.me))
        #expect(try await app.partner.fetchPairState() == nil)
        #expect(app.model.phase == .onboarding && app.model.session == nil)
        #expect(await app.backend.currentSession() == nil)
        #expect(app.purchases.signedInUser == nil)
        // Signing in again starts from scratch.
        #expect(app.flags.string("onboarding.done.\(TestApp.me.uuidString)") == nil)
    }

    @Test func deletionFailureKeepsTheAccount() async {
        let app = await TestApp()
        app.backend.setOffline(true)
        let model = SettingsModel(app: app.model)
        await model.deleteAccount()
        #expect(model.message != nil && app.model.phase == .ready && app.world.hasPerson(TestApp.me))
    }

    @Test func signOut() async {
        let app = await TestApp()
        #expect(app.purchases.signedInUser == TestApp.me)
        await SettingsModel(app: app.model).signOut()
        #expect(app.model.session == nil && app.purchases.signedInUser == nil)
    }
}

@MainActor @Suite struct PaywallModelTests {
    /// Decision M7 and feature spec §12: the headline and every price say it covers both.
    @Test func pricesCoverBothPartners() async throws {
        let app = await TestApp()
        let model = PaywallModel(app: app.model)
        await model.load()
        #expect(model.offers.map(\.product) == [.yearly, .lifetime] && model.selected == .yearly)
        #expect(model.priceLine(model.offers[0]) == "$39.99/year for both of you")
        #expect(model.priceLine(model.offers[1]) == "$119.99 once, for both of you")
        #expect(model.detailLine(model.offers[0]) == "14 days free, then $39.99/year for both of you")
        #expect(model.actionTitle == "Start 14 days free" && model.trialAvailable)
        #expect(model.benefits.count == 4)
    }

    /// The trial starts when the first partner opts in; the partner sees premium (pair premium from the backend).
    @Test func trialThenThePartnerHasPremium() async throws {
        let app = await TestApp()
        let model = PaywallModel(app: app.model)
        await model.load()
        await model.purchase()
        #expect(model.thanks && model.thanksLine == "Premium is on for you and Ana.")
        #expect(app.model.isPremium && app.model.premium.kind == .trial && app.model.premium.payerID == TestApp.me)
        let partnerView = try await app.partner.fetchPremium()
        #expect(partnerView.isPremium && partnerView.trialUsed)
        #expect(app.world.loggedEvents.contains("purchase_completed"))
        // The trial is counted once per pair: after it ends, it is not offered again.
        app.clock.advance(15 * 86400)
        await app.model.refreshPremium()
        #expect(!app.model.isPremium)
        let later = PaywallModel(app: app.model)
        await later.load()
        #expect(!later.trialAvailable && later.actionTitle == "Subscribe for both of you" && later.detailLine(later.offers[0]) == nil)
        await later.purchase()
        #expect(app.model.premium.kind == .subscription)
    }

    @Test func lifetime() async {
        let app = await TestApp()
        let model = PaywallModel(app: app.model)
        await model.load()
        model.selected = .lifetime
        #expect(model.actionTitle == "Get lifetime for both of you")
        await model.purchase()
        #expect(app.model.premium.kind == .lifetime && app.model.premium.expiresAt == nil)
    }

    @Test func cancelPendingAndFailureAreCalm() async {
        let app = await TestApp()
        let model = PaywallModel(app: app.model)
        await model.load()
        app.purchases.setBehavior(.cancel)
        await model.purchase()
        #expect(!model.thanks && model.message == nil && !app.model.isPremium)
        app.purchases.setBehavior(.pending)
        await model.purchase()
        #expect(model.message?.contains("waiting for approval") == true)
        app.purchases.setBehavior(.fail)
        await model.purchase()
        #expect(model.message == "The purchase didn't go through. Nothing was charged.")
        let unreachable = PaywallModel(app: app.model)
        await unreachable.load()
        #expect(unreachable.offers.isEmpty && unreachable.selectedOffer == nil && unreachable.message != nil)
    }

    @Test func restore() async {
        let app = await TestApp()
        let model = PaywallModel(app: app.model)
        await model.restore()
        #expect(model.message == "No earlier purchase was found for this Apple account." && !model.thanks)
    }

    /// Downgrade (§12): earned minutes are kept; premium features rest and return on resubscribe.
    @Test func downgradeKeepsMinutes() async {
        let app = await TestApp(premium: true)
        app.world.seedGrant(45, to: TestApp.me)
        await app.model.refreshMinutes()
        app.world.setEntitlement(nil, for: TestApp.me)
        await app.settle()
        #expect(!app.model.isPremium && app.model.myMinutes?.balance == 75)
        #expect(app.model.visibleChallenges.count == 5)
    }

    /// M2: on unpair the payer keeps premium, the other drops to free.
    @Test func unpairKeepsPremiumWithThePayer() async throws {
        let app = await TestApp()
        app.world.setEntitlement(.subscription, for: TestApp.partnerID)
        await app.settle()
        #expect(app.model.isPremium)
        try await app.model.unpair()
        #expect(!app.model.isPremium)
        #expect(try await app.partner.fetchPremium().isPremium)
    }
}

@MainActor @Suite struct AllowanceAndSignOutTests {
    /// P14: emergency minutes are chosen next to the daily maximum; only 15/30/45/60.
    @Test func emergencyAllowanceSetting() async {
        let app = await TestApp()
        let model = SettingsModel(app: app.model)
        #expect(model.emergencyAllowance == 15)
        await model.setEmergencyAllowance(45)
        #expect(app.model.settings.emergencyAllowanceMinutes == 45 && app.model.emergency.remaining == 45)
        await model.setEmergencyAllowance(20) // not a choice: ignored
        #expect(app.model.settings.emergencyAllowanceMinutes == 45)
    }

    /// P30: the confirmation says what signing out means before it happens.
    @Test func signOutExplanation() async {
        let paired = SettingsModel(app: await TestApp().model)
        #expect(paired.signOutExplanation == "Protected time pauses on this phone until you sign back in. You stay paired with Ana, and Ana will see that protected time is off on your phone.")
        let alone = SettingsModel(app: await TestApp(paired: false).model)
        #expect(alone.signOutExplanation == "Protected time pauses on this phone until you sign back in.")
    }
}
