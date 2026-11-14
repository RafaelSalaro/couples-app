import Backend
import Core
import FeatureSupport
import FeatureTestSupport
import Foundation
import QRCode
import Testing
@testable import UnlockFeature

@MainActor @Suite struct UnlockLengthAndAvailabilityTests {
    @Test func freeLengthsAndDefault() async {
        let app = await TestApp()
        let model = UnlockModel(app: app.model)
        #expect(model.length == 30 && model.lengths == [15, 30, 60] && !model.canStepLength)
        model.stepLength(by: 1) // 45 is premium only
        #expect(model.length == 30)
    }

    @Test func premiumStepsInFifteens() async {
        let app = await TestApp(premium: true)
        let model = UnlockModel(app: app.model)
        #expect(model.canStepLength)
        model.stepLength(by: 1)
        #expect(model.length == 45)
        model.stepLength(by: -2)
        #expect(model.length == 15)
        model.stepLength(by: -1)
        #expect(model.length == 15)
    }

    @Test func minutesAvailability() async throws {
        let app = await TestApp()
        let model = UnlockModel(app: app.model)
        #expect(model.minutesAvailability == .available)
        model.length = 60
        #expect(model.minutesAvailability == .notEnough(balance: 30))
        app.world.seedGrant(120, to: TestApp.me)
        await app.model.refreshMinutes()
        #expect(model.minutesAvailability == .available)
        await model.useMinutes()
        model.length = 15
        #expect(model.minutesAvailability == .overDailyMax(remainingToday: 0))
        #expect(model.minutesNote == "0 min left of the daily maximum you set.")
    }

    @Test func partnerMethodsNeedAPartner() async {
        let app = await TestApp(paired: false)
        let model = UnlockModel(app: app.model)
        #expect(!model.isPaired)
        await model.askPartner()
        #expect(model.message == "Invite your partner to use this." && model.flow == .idle)
        await model.handleScan("anything")
        #expect(model.started == nil && model.message != nil)
    }
}

@MainActor @Suite struct AskPartnerTests {
    @Test func goForItStartsTheUnlockWithoutSpendingMinutes() async throws {
        let app = await TestApp()
        let model = UnlockModel(app: app.model)
        model.reason = "Reply to a client"
        await model.askPartner()
        guard case .waiting(let request) = model.flow else {
            Issue.record("Not waiting")
            return
        }
        #expect(request.minutes == 30 && request.reason == "Reply to a client")
        #expect(model.waitingSecondsLeft == 300)
        try await app.partner.respondUnlockRequest(id: request.id, approve: true)
        await app.settle()
        model.tick()
        #expect(model.started?.method == .partnerApproval)
        #expect(model.startedLine?.replacingOccurrences(of: "\u{202F}", with: " ") == "Unlocked until 8:30 PM.")
        #expect(!app.blocking.isProtectedNow())
        #expect(app.model.myMinutes?.balance == 30)
    }

    @Test func letsWaitIsCalmAndCanAskAgain() async throws {
        let app = await TestApp()
        let model = UnlockModel(app: app.model)
        await model.askPartner()
        let request = try #require(model.flow.request)
        try await app.partner.respondUnlockRequest(id: request.id, approve: false)
        await app.settle()
        model.tick()
        #expect(model.outcomeLine == "Ana says let's wait — maybe later?")
        #expect(app.blocking.isProtectedNow() && model.started == nil)
        model.askAgain()
        #expect(model.flow == .idle && model.outcomeLine == nil)
    }

    @Test func expiresAfterFiveMinutes() async {
        let app = await TestApp()
        let model = UnlockModel(app: app.model)
        await model.askPartner()
        app.clock.advance(299)
        model.tick()
        #expect(model.waitingSecondsLeft == 1 && model.outcomeLine == nil)
        app.clock.advance(1)
        model.tick()
        #expect(model.outcomeLine == "No answer this time. You can try again or use your minutes.")
    }

    @Test func accountabilityCodeFromTheEmail() async throws {
        let app = await TestApp()
        let model = UnlockModel(app: app.model)
        await model.askPartner()
        #expect(!model.codeEntryAvailable)
        app.clock.advance(120) // email fallback after 2 minutes
        #expect(model.codeEntryAvailable)
        model.codeEntry = "12345"
        #expect(!model.canRedeemCode)
        model.codeEntry = "000000"
        await model.redeemCode()
        #expect(model.message == "That code didn't match. Check it with Ana.")
        model.codeEntry = FakeWorld.fixedAccountabilityCode
        await model.redeemCode()
        #expect(model.started?.method == .accountabilityCode && !app.blocking.isProtectedNow())
    }

    @Test func tooManyRequestsIsExplainedKindly() async {
        let app = await TestApp()
        for _ in 0..<3 {
            let model = UnlockModel(app: app.model)
            await model.askPartner()
        }
        let model = UnlockModel(app: app.model)
        await model.askPartner()
        #expect(model.message == "That's a few asks in a row. Give it a little while, or use your minutes.")
    }

    @Test func offlineIsExplained() async {
        let app = await TestApp()
        app.backend.setOffline(true)
        let model = UnlockModel(app: app.model)
        await model.askPartner()
        #expect(model.message == "You're offline. This needs a connection — try again when you're back.")
        await model.useMinutes()
        #expect(model.started == nil)
    }
}

@MainActor @Suite struct MinutesAndEmergencyUnlockTests {
    @Test func spendingMinutesUnlocksAndUpdatesTheBalance() async {
        let app = await TestApp()
        let model = UnlockModel(app: app.model)
        model.length = 15
        await model.useMinutes()
        #expect(model.started?.method == .minutes)
        #expect(app.model.myMinutes?.balance == 15)
        #expect(app.store.load().activeUnlock?.endsAt == app.clock.now.addingTimeInterval(900))
    }

    @Test func emergencyWorksWithZeroMinutesAndNoPartnerOncePerWeek() async {
        let app = await TestApp(paired: false)
        let model = UnlockModel(app: app.model)
        #expect(model.emergencyAvailableAt == nil)
        await model.useEmergency()
        #expect(model.started?.method == .emergency)
        #expect(app.model.myMinutes?.balance == -15)
        #expect(app.store.load().activeUnlock?.endsAt == app.clock.now.addingTimeInterval(900))
        let again = UnlockModel(app: app.model)
        #expect(again.emergencyAvailableAt == app.clock.now.addingTimeInterval(7 * 86400))
        #expect(again.emergencyNote == "Used this week. Available again on Tuesday.")
        await again.useEmergency()
        #expect(again.started == nil && again.message == "You've used this week's emergency unlock.")
        #expect(again.minutesAvailability == .inDebt(15))
    }

    @Test func unlockingAgainExtendsTheWindow() async {
        let app = await TestApp()
        app.world.seedGrant(60, to: TestApp.me)
        await app.model.refreshMinutes()
        let first = UnlockModel(app: app.model)
        first.length = 15
        await first.useMinutes()
        app.clock.advance(300)
        let second = UnlockModel(app: app.model)
        second.length = 30
        await second.useMinutes()
        #expect(second.started?.until == testDate(2026, 11, 10, 20, 45))
    }
}

@MainActor @Suite struct QRUnlockFlowTests {
    func partnerCode(_ app: TestApp, at date: Date? = nil) throws -> String {
        let secret = try #require(try app.world.qrSecret(TestApp.partnerID))
        return QRUnlockPayload(secret: secret, at: date ?? app.clock.now).string
    }

    @Test func scanningUnlocksOfflineAndSyncsLater() async throws {
        let app = await TestApp()
        let code = try partnerCode(app)
        app.backend.setOffline(true)
        let model = UnlockModel(app: app.model)
        model.length = 15
        await model.handleScan(code)
        #expect(model.started?.method == .qr && !app.blocking.isProtectedNow())
        #expect(app.model.deps.pendingQRUnlocks.all.count == 1) // logged locally
        #expect(app.world.unlocks(of: TestApp.me).isEmpty)
        app.backend.setOffline(false)
        await app.model.refresh()
        #expect(app.model.deps.pendingQRUnlocks.all.isEmpty)
        #expect(app.world.unlocks(of: TestApp.me).map(\.method) == [.qr])
        // Free: no minutes spent.
        #expect(app.model.myMinutes?.balance == 30)
    }

    @Test func aUsedCodeCannotBeReused() async throws {
        let app = await TestApp()
        let code = try partnerCode(app)
        let model = UnlockModel(app: app.model)
        await model.handleScan(code)
        let again = UnlockModel(app: app.model)
        await again.handleScan(code)
        #expect(again.started == nil)
        #expect(again.message == "That code was already used. It changes every 30 seconds — scan the next one.")
        // The next code extends the unlock: being together has no limit.
        app.clock.advance(30)
        await again.handleScan(try partnerCode(app))
        #expect(again.started != nil)
    }

    @Test func oldAndForeignCodesAreExplained() async throws {
        let app = await TestApp()
        let old = try partnerCode(app, at: app.clock.now.addingTimeInterval(-120))
        let model = UnlockModel(app: app.model)
        await model.handleScan(old)
        #expect(model.message == "That code has changed. Ask Ana to show the current one.")
        await model.handleScan("https://example.com")
        #expect(model.message == "That isn't Ana's unlock code. Ask them to open “Show my code”.")
        let stranger = QRUnlockPayload(secret: QRSecret(pairID: UUID(), secret: Data(repeating: 1, count: 20), version: 1), at: app.clock.now)
        await model.handleScan(stranger.string)
        #expect(model.started == nil && app.blocking.isProtectedNow())
    }

    @Test func showMyCodeRotatesEveryThirtySeconds() async throws {
        let app = await TestApp()
        let model = ShowCodeModel(app: app.model)
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try #require(model.payload(at: t))
        #expect(model.payload(at: t.addingTimeInterval(29)) == first)
        #expect(model.payload(at: t.addingTimeInterval(30)) != first)
        #expect(model.secondsRemaining(at: t.addingTimeInterval(10)) == 20)
        // What I show is what my partner's phone accepts.
        let partnerSecret = try #require(try app.world.qrSecret(TestApp.partnerID))
        #expect(QRUnlockVerifier(secret: partnerSecret, used: InMemoryUsedCounterStore()).redeem(first, at: t) == .success(TOTP.counter(at: t)))
        let unpaired = await TestApp(paired: false)
        #expect(ShowCodeModel(app: unpaired.model).payload(at: t) == nil)
    }
}

@MainActor @Suite struct IncomingRequestTests {
    @Test func goForIt() async throws {
        let app = await TestApp()
        let request = try await app.partner.createUnlockRequest(minutes: 30, reason: "Reply to a client")
        await app.settle()
        let model = IncomingRequestModel(app: app.model, request: request)
        #expect(model.title == "Ana asks for 30 min")
        await model.respond(approve: true)
        #expect(model.answered && app.model.sheet == nil && app.model.incomingUnlockRequests.isEmpty)
        #expect(app.world.unlocks(of: TestApp.partnerID).first?.method == .partnerApproval)
    }

    @Test func letsWaitAndLateAnswers() async throws {
        let app = await TestApp()
        let request = try await app.partner.createUnlockRequest(minutes: 15, reason: nil)
        let model = IncomingRequestModel(app: app.model, request: request)
        await model.respond(approve: false)
        #expect(model.answered && app.world.unlocks(of: TestApp.partnerID).isEmpty)
        let late = try await app.partner.createUnlockRequest(minutes: 15, reason: nil)
        let lateModel = IncomingRequestModel(app: app.model, request: late)
        app.clock.advance(301)
        #expect(lateModel.isExpired)
        await lateModel.respond(approve: true)
        #expect(!lateModel.answered && lateModel.message == "This request has already ended.")
    }
}
