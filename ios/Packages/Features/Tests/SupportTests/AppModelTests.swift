import Backend
import Blocking
import Core
import FeatureTestSupport
import Foundation
import Testing
@testable import FeatureSupport

@MainActor @Suite struct AppModelLifecycleTests {
    @Test func signedOutStartsOnboarding() async {
        let app = await TestApp(signedIn: false, paired: false, ready: false)
        #expect(app.model.phase == .onboarding && app.model.session == nil)
        #expect(!app.model.protectionNeedsAttention)
    }

    @Test func returningUserGoesStraightToTheApp() async {
        let app = await TestApp()
        #expect(app.model.phase == .ready)
        #expect(app.model.partnerName == "Ana" && app.model.myName == "Rafa")
        #expect(app.model.myMinutes?.balance == 30 && app.model.partnerMinutes?.balance == 30)
        #expect(app.model.streak.currentLength == 4)
        #expect(app.model.schedules == [app.model.effectiveSchedules[0]])
        #expect(app.model.visibleChallenges.count == 5) // free tier: the 5 presets
    }

    @Test func signedInButNotOnboardedResumesOnboarding() async {
        let app = await TestApp(paired: false, ready: false)
        #expect(app.model.phase == .onboarding && app.model.session != nil)
        await app.model.finishOnboarding()
        #expect(app.model.phase == .ready)
        #expect(app.world.loggedEvents == ["onboarding_completed"])
    }

    @Test func sharedStateFeedsExtensionsAndWidgets() async {
        let app = await TestApp()
        let state = app.store.load()
        #expect(state.partnerName == "Ana" && state.myBalance == 30 && state.partnerBalance == 30 && state.streak == 4)
        #expect(state.schedules.count == 1 && state.protectionConfigured)
        #expect(app.model.protectionPhase == .protected(until: testDate(2026, 11, 11, 9)))
        #expect(app.blocking.isProtectedNow())
    }

    @Test func signOutClearsAccountState() async {
        let app = await TestApp()
        await app.model.signOut()
        #expect(app.model.phase == .onboarding && app.model.session == nil && app.model.pair == nil)
        #expect(app.store.load().partnerName == nil && app.store.load().myBalance == nil)
        // Protected time stays on the phone.
        #expect(app.store.load().schedules.count == 1)
    }

    @Test func offlineKeepsTheLastKnownState() async {
        let app = await TestApp()
        app.backend.setOffline(true)
        await app.model.refresh()
        #expect(app.model.isOffline)
        #expect(app.model.myMinutes?.balance == 30 && app.model.pair != nil)
        app.backend.setOffline(false)
        await app.model.refresh()
        #expect(!app.model.isOffline)
    }
}

@MainActor @Suite struct AppModelEventTests {
    @Test func approvedRequestStartsTheUnlockOnce() async throws {
        let app = await TestApp()
        let request = try await app.backend.createUnlockRequest(minutes: 30, reason: nil)
        try await app.partner.respondUnlockRequest(id: request.id, approve: true)
        await app.settle()
        #expect(app.model.outgoingUpdate?.request.status == .approved)
        #expect(app.store.load().activeUnlock?.endsAt == app.clock.now.addingTimeInterval(1800))
        #expect(!app.blocking.isProtectedNow())
        #expect(app.model.unlockStartCount == 1)
        // Hearing about the same unlock again must not extend the window.
        let unlock = try #require(app.model.outgoingUpdate?.unlock)
        await app.model.beginUnlock(unlock)
        #expect(app.store.load().activeUnlock?.endsAt == app.clock.now.addingTimeInterval(1800))
        #expect(app.model.unlockStartCount == 1)
    }

    @Test func incomingRequestOpensTheAnswerSheetAndClosesWhenAnswered() async throws {
        let app = await TestApp()
        let request = try await app.partner.createUnlockRequest(minutes: 30, reason: "Reply to a client")
        await app.settle()
        #expect(app.model.sheet == .incomingRequest(request))
        #expect(app.model.incomingUnlockRequests == [request])
        try await app.backend.respondUnlockRequest(id: request.id, approve: false)
        await app.settle()
        #expect(app.model.sheet == nil && app.model.incomingUnlockRequests.isEmpty)
    }

    @Test func kudosCelebratesTheReceiver() async throws {
        let app = await TestApp(premium: true)
        let kudos = try await app.partner.giveKudos(minutes: 10, message: "You made me laugh today", challengeID: nil)
        await app.settle()
        #expect(app.model.celebration == .kudos(kudos))
        #expect(app.model.myMinutes?.balance == 40)
        #expect(app.store.load().myBalance == 40)
    }

    @Test func partnerUnpairingGivesAGentleNote() async throws {
        let app = await TestApp()
        try await app.partner.unpair()
        await app.settle()
        #expect(app.model.pair == nil)
        #expect(app.model.notice == "Ana ended your pairing.")
        #expect(app.model.myMinutes?.balance == 0)
        #expect(app.store.load().partnerName == nil && app.store.load().streak == nil)
        // Protected time stays on this phone.
        #expect(app.blocking.isProtectedNow())
    }

    @Test func pairingCelebrates() async throws {
        let app = await TestApp(paired: false)
        let invite = try await app.backend.createInvite()
        _ = try await app.partner.acceptInvite(codeOrToken: invite.code)
        await app.settle()
        #expect(app.model.celebration == .paired(partnerName: "Ana"))
        #expect(app.model.myMinutes?.balance == 30)
        #expect(app.model.deps.qrSecrets.load() != nil)
    }

    @Test func streakMilestoneCelebratesOnlyWhenReached() async {
        let app = await TestApp()
        app.world.advanceStreak(for: TestApp.me) // 5
        await app.settle()
        #expect(app.model.celebration == nil && app.model.streak.currentLength == 5)
        app.world.advanceStreak(for: TestApp.me)
        app.world.advanceStreak(for: TestApp.me) // 7
        await app.settle()
        #expect(app.model.celebration == .streak(7))
        #expect(app.store.load().streak == 7)
    }

    @Test func premiumReachesThePartnerAndUnlocksTheLibrary() async {
        let app = await TestApp()
        app.world.setEntitlement(.subscription, for: TestApp.partnerID)
        await app.settle()
        #expect(app.model.isPremium && app.model.premium.payerID == TestApp.partnerID)
        #expect(app.model.visibleChallenges.count > 5)
    }

    @Test func partnerStatusIsNeutral() async throws {
        let app = await TestApp()
        try await app.partner.setProtectedTimeOff(true)
        await app.settle()
        #expect(app.model.partnerProtectionIsOff)
        try await app.partner.setProtectedTimeOff(false)
        await app.settle()
        #expect(!app.model.partnerProtectionIsOff)
    }
}

@MainActor @Suite struct AppModelActionTests {
    @Test func revokedScreenTimeIsDetectedAndReportedOnce() async throws {
        let app = await TestApp()
        #expect(!app.model.protectionNeedsAttention)
        app.blocking.revokeAuthorization()
        await app.model.becameActive()
        #expect(app.model.protectionNeedsAttention)
        #expect(try await app.partner.fetchPairState()?.partner.protectedTimeOffSince != nil)
        // Granting it again clears the status for the partner.
        try await app.model.requestScreenTimeAccess()
        #expect(!app.model.protectionNeedsAttention)
        #expect(try await app.partner.fetchPairState()?.partner.protectedTimeOffSince == nil)
    }

    @Test func shieldPromptOpensTheUnlockSheet() async {
        let app = await TestApp()
        app.store.update { $0.unlockPromptRequestedAt = app.clock.now.addingTimeInterval(-30) }
        await app.model.becameActive()
        #expect(app.model.sheet == .unlock)
        #expect(app.store.load().unlockPromptRequestedAt == nil)
        // A stale tap from long ago is ignored.
        app.model.sheet = nil
        app.store.update { $0.unlockPromptRequestedAt = app.clock.now.addingTimeInterval(-3600) }
        await app.model.becameActive()
        #expect(app.model.sheet == nil)
    }

    @Test func deepLinks() async throws {
        let app = await TestApp()
        await app.model.open(URL(string: "couplesapp://unlock")!)
        #expect(app.model.sheet == .unlock)
        let request = try await app.partner.createUnlockRequest(minutes: 15, reason: nil)
        app.model.sheet = nil
        await app.model.open(URL(string: "couplesapp://request/\(request.id.uuidString)")!)
        #expect(app.model.sheet == .incomingRequest(request))
        let id = UUID()
        await app.model.open(URL(string: "couplesapp://challenge/\(id.uuidString)")!)
        #expect(app.model.place == .together && app.model.focusedChallengeID == id)
        await app.model.open(URL(string: "https://elsewhere.example/i/abc")!)
        #expect(app.model.pendingInvite == nil)
    }

    @Test func inviteLinkWaitsUntilItCanBeUsed() async {
        let signedOut = await TestApp(signedIn: false, paired: false, ready: false)
        await signedOut.model.open(URL(string: "https://example.com/i/sometoken")!)
        #expect(signedOut.model.pendingInvite == "sometoken" && signedOut.model.sheet == nil)
        let unpaired = await TestApp(paired: false)
        await unpaired.model.open(URL(string: "https://example.com/i/sometoken")!)
        #expect(unpaired.model.sheet == .invite)
    }

    @Test func magicLinkCallbackSignsIn() async throws {
        let app = await TestApp(signedIn: false, paired: false, ready: false)
        try await app.backend.sendMagicLink(email: "rafa@example.com")
        await app.model.open(FakeBackend.magicLink(for: "rafa@example.com", scheme: "couplesapp"))
        #expect(app.model.session?.userID == TestApp.me)
        #expect(app.model.phase == .onboarding)
        await app.model.open(URL(string: "couplesapp://login-callback?email=unknown@example.com")!)
        #expect(app.model.session?.userID == TestApp.me)
    }

    @Test func pausingFewerAppsWaitsForThePartnerAndTokensStayLocal() async throws {
        let app = await TestApp()
        let more = MockBlockingService.selection(ids: MockBlockingService.suggested.union(["category.games"]))
        #expect(try await app.model.saveSelection(more) == .saved)
        let fewer = MockBlockingService.selection(ids: ["category.social"])
        #expect(try await app.model.saveSelection(fewer) == .waitingForPartner)
        #expect(app.blocking.currentSelection() == more)
        let request = try #require(app.model.scheduleRequests.first)
        #expect(request.proposed == .fewerPausedApps)
        try await app.partner.respondScheduleChange(requestID: request.id, approve: true)
        await app.settle()
        #expect(app.blocking.currentSelection() == fewer)
        #expect(app.model.scheduleRequests.isEmpty)
    }

    @Test func letsTalkKeepsThePausedApps() async throws {
        let app = await TestApp()
        let current = app.blocking.currentSelection()
        _ = try await app.model.saveSelection(MockBlockingService.selection(ids: ["category.social"]))
        let request = try #require(app.model.scheduleRequests.first)
        try await app.partner.respondScheduleChange(requestID: request.id, approve: false)
        await app.settle()
        #expect(app.blocking.currentSelection() == current)
    }

    @Test func unpairedSelectionChangesApplyDirectly() async throws {
        let app = await TestApp(paired: false)
        #expect(try await app.model.saveSelection(MockBlockingService.selection(ids: ["category.social"])) == .saved)
    }

    @Test func offlineQRUnlocksSyncLater() async throws {
        let app = await TestApp()
        app.backend.setOffline(true)
        app.model.deps.pendingQRUnlocks.add(QRUnlockEvent(counter: 77, minutes: 15, startedAt: app.clock.now))
        await app.model.syncPendingQRUnlocks()
        #expect(app.model.deps.pendingQRUnlocks.all.count == 1)
        app.backend.setOffline(false)
        await app.model.syncPendingQRUnlocks()
        #expect(app.model.deps.pendingQRUnlocks.all.isEmpty)
        #expect(app.world.unlocks(of: TestApp.me).first?.method == .qr)
    }

    @Test func endingAnUnlockEarly() async throws {
        let app = await TestApp()
        let unlock = try await app.backend.spendMinutesUnlock(minutes: 15, clientEventID: UUID())
        await app.model.beginUnlock(unlock)
        #expect(!app.blocking.isProtectedNow())
        await app.model.endUnlockEarly()
        #expect(app.blocking.isProtectedNow())
    }

    @Test func downgradeHidesExtraSchedulesWithoutDeletingThem() async throws {
        let app = await TestApp(premium: true)
        let lunch = ProtectedSchedule(name: "Lunch", startLocal: LocalTime(hour: 12), endLocal: LocalTime(hour: 13))
        try await app.model.submitSchedule(scheduleID: nil, proposal: .schedule(lunch))
        #expect(app.model.effectiveSchedules.count == 2 && app.store.load().schedules.count == 2)
        app.world.setEntitlement(nil, for: TestApp.me)
        await app.settle()
        #expect(!app.model.isPremium)
        #expect(app.model.schedules.count == 2) // kept
        #expect(app.model.effectiveSchedules.count == 1 && app.store.load().schedules.count == 1) // hidden
        app.world.setEntitlement(.subscription, for: TestApp.me)
        await app.settle()
        #expect(app.store.load().schedules.count == 2) // back on resubscribe
    }
}

@Suite struct SupportTextTests {
    let en = Locale(identifier: "en_US")

    @Test func scheduleWording() {
        #expect(ScheduleText.range(.standard(), locale: en).replacingOccurrences(of: "\u{202F}", with: " ") == "6:00 PM – 9:00 AM")
        #expect(ScheduleText.days(Set(1...7)) == "Every day")
        #expect(ScheduleText.days([1, 2, 3, 4, 5]) == "Weekdays")
        #expect(ScheduleText.days([6, 7]) == "Weekends")
        #expect(ScheduleText.days([1, 3, 7], locale: en) == "Mon, Wed, Sun")
        #expect(ScheduleText.localTime(from: ScheduleText.date(for: LocalTime(hour: 18, minute: 30))) == LocalTime(hour: 18, minute: 30))
        #expect(MinutesText.short(30) == "30 min")
    }

    /// Voice rules (doc 10): nothing that scolds, no "blocked", "denied", "failed", "permission" or "violation".
    @Test func errorCopyNeverScolds() {
        let banned = ["block", "denied", "deny", "failed", "violation", "permission", "penalty", "forbidden", "not allowed"]
        for code in BackendError.Code.allCases {
            let text = Friendly.message(for: BackendError(code)).lowercased()
            #expect(!text.isEmpty)
            for word in banned { #expect(!text.contains(word), "\(code): \(text)") }
        }
        for error in [BlockingError.authorizationDenied, .notAuthorized, .unlockTooShort, .system("x")] {
            let text = Friendly.message(for: error).lowercased()
            for word in banned { #expect(!text.contains(word), "\(text)") }
        }
    }

    @Test func brandLinks() {
        let brand = BrandInfo(displayName: "Name", urlScheme: "couplesapp", websiteDomain: "example.com")
        #expect(brand.privacyURL.absoluteString == "https://example.com/privacy")
        #expect(brand.safetyURL.absoluteString == "https://example.com/safety")
    }
}
