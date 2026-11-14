import Backend
import Core
import FeatureSupport
import FeatureTestSupport
import Foundation
import Testing
@testable import PairingFeature

@MainActor @Suite struct PairingModelTests {
    @Test func inviteThenPartnerJoins() async throws {
        let app = await TestApp(paired: false)
        let model = PairingModel(app: app.model)
        await model.createInvite()
        let invite = try #require(model.invite)
        #expect(invite.code.count == 6)
        #expect(model.shareText(for: invite).contains(invite.link.absoluteString))
        #expect(model.shareText(for: invite).contains(app.model.deps.brand.displayName))
        _ = try await app.partner.acceptInvite(codeOrToken: invite.code)
        await app.settle()
        #expect(model.isPaired && app.model.partnerName == "Ana")
        #expect(app.model.celebration == .paired(partnerName: "Ana"))
        #expect(app.world.loggedEvents.contains("invite_created"))
    }

    @Test func joinWithTypedCode() async throws {
        let app = await TestApp(paired: false)
        app.world.seedInvite(from: TestApp.partnerID, code: "ANA234")
        let model = PairingModel(app: app.model)
        #expect(!model.canJoin)
        model.codeEntry = "ana 2"
        #expect(!model.canJoin)
        model.codeEntry = "ana234"
        #expect(model.canJoin)
        await model.join()
        #expect(model.isPaired && model.message == nil)
        #expect(app.model.myMinutes?.balance == 30)
        #expect(app.model.deps.qrSecrets.load() != nil)
    }

    @Test func joinWithScannedLinkOrPendingUniversalLink() async {
        let app = await TestApp(paired: false)
        app.world.seedInvite(from: TestApp.partnerID, code: "ANA234", token: "tok123")
        let model = PairingModel(app: app.model)
        #expect(model.token(from: "https://example.com/i/tok123") == "tok123")
        #expect(model.token(from: " ana234 ") == "ANA234")
        await model.join(with: "https://example.com/i/tok123")
        #expect(model.isPaired)

        let other = await TestApp(paired: false)
        other.world.seedInvite(from: TestApp.partnerID, code: "ANA234", token: "tok123")
        await other.model.open(URL(string: "https://example.com/i/tok123")!)
        let fromLink = PairingModel(app: other.model)
        #expect(fromLink.codeEntry == "tok123")
        await fromLink.join()
        #expect(fromLink.isPaired && other.model.pendingInvite == nil)
    }

    @Test func wrongAndExpiredCodesGetKindMessages() async throws {
        let app = await TestApp(paired: false)
        let model = PairingModel(app: app.model)
        model.codeEntry = "NOPE22"
        await model.join()
        #expect(model.message == "That code didn't match. Check it with your partner and try again.")
        app.world.seedInvite(from: TestApp.partnerID, code: "ANA234")
        app.clock.advance(73 * 3600)
        model.codeEntry = "ANA234"
        await model.join()
        #expect(model.message == "That invite has expired. Ask your partner for a new one.")
        #expect(!model.isPaired)
    }

    @Test func revokeInvite() async throws {
        let app = await TestApp(paired: false)
        let model = PairingModel(app: app.model)
        await model.createInvite()
        let code = try #require(model.invite?.code)
        await model.revokeInvite()
        #expect(model.invite == nil)
        await #expect(throws: BackendError.self) { _ = try await app.partner.acceptInvite(codeOrToken: code) }
    }

    /// §3: either partner can unpair at any time, instantly, without the other's approval.
    @Test func unpairIsInstantAndUnilateral() async throws {
        let app = await TestApp()
        let model = PairingModel(app: app.model)
        await model.unpair()
        #expect(!model.isPaired)
        #expect(app.model.notice == "You're no longer paired. Your protected time stays as it is.")
        #expect(app.model.myMinutes?.balance == 0)
        #expect(app.model.deps.qrSecrets.load() == nil)
        #expect(try await app.partner.fetchPairState() == nil)
        #expect(app.blocking.isProtectedNow())
        // Inviting works again right away.
        await model.createInvite()
        #expect(model.invite != nil)
    }

    @Test func invitingWhilePairedIsNotOffered() async {
        let app = await TestApp()
        let model = PairingModel(app: app.model)
        await model.createInvite()
        #expect(model.invite == nil && model.message == "You're already paired.")
    }

    @Test func renewingTheUnlockCode() async throws {
        let app = await TestApp()
        let before = try #require(app.model.deps.qrSecrets.load())
        let model = PairingModel(app: app.model)
        await model.rotateSecret()
        let after = try #require(app.model.deps.qrSecrets.load())
        #expect(after.version == before.version + 1 && after.secret != before.secret)
    }

    @Test func codeNormalizing() {
        #expect(PairingModel.normalizedCode("ab-c1 23xyz") == "ABC123")
    }
}
