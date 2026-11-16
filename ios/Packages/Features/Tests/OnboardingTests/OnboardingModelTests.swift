import Backend
import Blocking
import Core
import FeatureSupport
import FeatureTestSupport
import Foundation
import Testing
@testable import OnboardingFeature

@MainActor @Suite struct OnboardingModelTests {
    /// Feature spec §2: the steps in order, from install to ready. Apple shared the name, so
    /// the name step is skipped (P27); there is no relationship step (P3).
    @Test func fullFlowFromInstallToReady() async throws {
        let app = await TestApp(signedIn: false, paired: false, ready: false, start: testDate(2026, 11, 10, 14, 0))
        let model = OnboardingModel(app: app.model)
        #expect(model.step == .welcome && !model.canGoBack)
        model.advance()
        #expect(model.step == .signIn)
        await model.signInWithApple()
        #expect(app.model.session?.userID == TestApp.me)
        #expect(app.model.profile?.displayName == "Rafa")
        #expect(model.step == .invite && !model.canGoBack)
        model.advance() // continue alone
        #expect(model.step == .notifications)
        await model.allowNotifications()
        #expect(model.step == .screenTime)
        await model.allowScreenTime()
        #expect(model.step == .chooseApps && app.blocking.authorizationStatus == .approved)
        #expect(!model.canSaveApps) // nothing is pre-selected: the person chooses
        model.selection = MockBlockingService.selection(ids: MockBlockingService.suggested)
        await model.saveApps()
        #expect(model.step == .protectedTime)
        #expect(model.schedule.startLocal == LocalTime(hour: 18) && model.schedule.endLocal == LocalTime(hour: 9))
        await model.saveSchedule()
        #expect(model.step == .minutes)
        #expect(model.startingMinutes == 30 && model.dailyMax == 60 && model.emergencyAllowance == 15)
        model.emergencyAllowance = 30
        await model.saveMinutes()
        #expect(app.model.settings.emergencyAllowanceMinutes == 30)
        #expect(model.step == .ready)
        #expect(model.readyLine.replacingOccurrences(of: "\u{202F}", with: " ") == "Protected time starts at 6:00 PM.")
        await model.finish()
        #expect(app.model.phase == .ready)
        #expect(app.model.settings.onboardedAt != nil) // a returning sign-in can skip onboarding (P29)
        #expect(app.store.load().protectionConfigured)
        #expect(!app.blocking.isProtectedNow()) // 2 PM
        app.clock.set(testDate(2026, 11, 10, 18, 0))
        #expect(app.blocking.isProtectedNow())
    }

    @Test func editedChoicesAreSaved() async throws {
        let app = await TestApp(paired: false, ready: false)
        let model = OnboardingModel(app: app.model)
        model.schedule.startLocal = LocalTime(hour: 19)
        model.schedule.endLocal = LocalTime(hour: 8)
        await model.saveSchedule()
        // Unpaired: even a shorter schedule applies directly.
        #expect(app.model.schedules.first?.startLocal == LocalTime(hour: 19) && !model.scheduleWaitsForPartner)
        model.startingMinutes = 45
        model.dailyMax = 90
        await model.saveMinutes()
        #expect(app.model.settings.startingMinutes == 45 && app.model.settings.dailyMaxMinutes == 90)
        // The chosen starting balance is granted at pairing.
        let invite = try await app.backend.createInvite()
        _ = try await app.partner.acceptInvite(codeOrToken: invite.code)
        #expect(try await app.backend.fetchMinutes().mine.balance == 45)
    }

    @Test func shorterScheduleAfterJoiningWaitsForThePartner() async {
        let app = await TestApp(paired: true, ready: false)
        let model = OnboardingModel(app: app.model)
        model.schedule.startLocal = LocalTime(hour: 20)
        await model.saveSchedule()
        #expect(model.scheduleWaitsForPartner)
        #expect(app.model.schedules.first?.startLocal == LocalTime(hour: 18))
        #expect(app.model.scheduleRequests.count == 1)
        // A longer one applies at once.
        let other = OnboardingModel(app: app.model)
        other.schedule.startLocal = LocalTime(hour: 17)
        await other.saveSchedule()
        #expect(!other.scheduleWaitsForPartner && app.model.schedules.first?.startLocal == LocalTime(hour: 17))
    }

    @Test func decliningScreenTimeIsGentleAndSkipsThePicker() async {
        let app = await TestApp(paired: false, ready: false)
        let model = OnboardingModel(app: app.model)
        app.blocking.setAuthorizationOutcome(.denied)
        await model.allowScreenTime()
        #expect(model.screenTimeDeclined && model.message == nil)
        #expect(model.next(after: .screenTime) == .protectedTime)
        #expect(model.previous(before: .protectedTime) == .screenTime)
        #expect(model.readyLine == "Turn on Screen Time access whenever you're ready, and protected time will start.")
        app.blocking.setAuthorizationOutcome(.approved)
        await model.allowScreenTime()
        #expect(!model.screenTimeDeclined && model.next(after: .screenTime) == .chooseApps)
    }

    @Test func magicLinkSignIn() async {
        let app = await TestApp(signedIn: false, paired: false, ready: false)
        let model = OnboardingModel(app: app.model)
        model.advance()
        model.email = "not an email"
        #expect(!model.emailLooksValid)
        model.email = " sam@example.com "
        #expect(model.emailLooksValid)
        await model.sendMagicLink()
        #expect(model.magicLinkSentTo == "sam@example.com" && model.demoLink != nil)
        await model.openDemoLink()
        // Email never provides a name: the next step asks for one (P27).
        #expect(app.model.session?.email == "sam@example.com" && model.step == .name)
    }

    @Test func progressIsRememberedAcrossLaunches() async {
        let app = await TestApp(paired: false, ready: false)
        let model = OnboardingModel(app: app.model)
        #expect(model.step == .invite)
        model.advance()
        model.advance()
        #expect(model.step == .screenTime)
        #expect(OnboardingModel(app: app.model).step == .screenTime)
        model.back()
        #expect(OnboardingModel(app: app.model).step == .notifications)
        #expect(model.progress > 0 && model.progress < 1)
    }

    @Test func cancellingAppleSignInSaysNothing() async {
        struct Cancelling: AppleSignInProviding {
            func credential() async throws -> AppleCredential { throw SignInError.cancelled }
        }
        let base = await TestApp(signedIn: false, paired: false, ready: false)
        var deps = base.model.deps
        deps.appleSignIn = Cancelling()
        let model = OnboardingModel(app: AppModel(deps: deps))
        model.advance()
        await model.signInWithApple()
        #expect(model.message == nil && model.step == .signIn)
    }

    @Test func readyLineWhenAlreadyInsideProtectedTime() async {
        let app = await TestApp(paired: false, ready: true, start: testDate(2026, 11, 10, 22, 0))
        let model = OnboardingModel(app: app.model)
        #expect(model.readyLine.replacingOccurrences(of: "\u{202F}", with: " ") == "Protected time is on until 9:00 AM.")
    }
}

@MainActor @Suite struct NameAndReturningTests {
    /// P27: without a name from Apple (hidden or not shared), the step right after sign-in asks for one; it is required.
    @Test func nameStepWhenAppleSharesNoName() async {
        let app = await TestApp(signedIn: false, paired: false, ready: false)
        _ = app.world.addPerson(id: TestApp.me, name: nil, email: "rafa@example.com", timeZone: testZone)
        let model = OnboardingModel(app: app.model)
        model.advance()
        await model.signInWithApple()
        #expect(model.step == .name && !model.canGoBack)
        model.name = "   "
        #expect(!model.canSaveName)
        await model.saveName()
        #expect(model.step == .name)
        model.name = " Rafa "
        await model.saveName()
        #expect(app.model.profile?.displayName == "Rafa" && model.step == .invite)
    }

    /// P29: signing back in restores everything and skips completed onboarding.
    @Test func signingBackInGoesStraightToTheApp() async throws {
        let app = await TestApp()
        let pairBefore = app.model.pair?.partner.id
        await app.model.signOut()
        #expect(app.model.phase == .onboarding && app.model.session == nil)
        let session = try await app.backend.signInWithApple(idToken: "demo", nonce: nil, fullName: nil)
        await app.model.signedIn(session)
        #expect(app.model.phase == .ready)
        #expect(app.model.pair?.partner.id == pairBefore && app.model.myMinutes?.balance == 30)
    }

    /// P29 on a new phone: only what lives on the phone is asked again (here, the chosen apps).
    @Test func returningOnANewPhoneAsksOnlyForWhatThePhoneLacks() async throws {
        let app = await TestApp()
        app.world.seedOnboarded(TestApp.me)
        await app.model.signOut()
        app.store.saveSelectionData(nil) // a new phone: no apps chosen here yet
        let session = try await app.backend.signInWithApple(idToken: "demo", nonce: nil, fullName: nil)
        await app.model.signedIn(session)
        #expect(app.model.phase == .onboarding)
        let model = OnboardingModel(app: app.model)
        model.sessionChanged()
        #expect(model.firstStepAfterSignIn() == .chooseApps)
        #expect(model.next(after: .chooseApps) == .ready)
        #expect(!model.canGoBack)
    }
}

@MainActor @Suite struct SignInRoutingRaceTests {
    /// Found in UI tests: the view reacts to the session before the profile has loaded. Routing
    /// then must wait, or a person whose name Apple shared is asked for it again.
    @Test func routingWaitsForTheAccountToLoad() async throws {
        let app = await TestApp(signedIn: false, paired: false, ready: false)
        let model = OnboardingModel(app: app.model)
        model.advance()
        #expect(model.step == .signIn)
        let session = try await app.backend.signInWithApple(idToken: "demo", nonce: nil, fullName: nil)
        // What the view's onChange(of: session) sees mid-sign-in:
        let signingIn = Task { await app.model.signedIn(session) }
        await Task.yield()
        if app.model.isLoadingAccount { model.sessionChanged() }
        #expect(model.step == .signIn) // not .name
        await signingIn.value
        model.sessionChanged()
        #expect(model.step == .invite)
    }
}
