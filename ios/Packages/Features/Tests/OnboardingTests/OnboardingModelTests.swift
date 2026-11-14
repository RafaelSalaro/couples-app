import Backend
import Blocking
import Core
import FeatureSupport
import FeatureTestSupport
import Foundation
import Testing
@testable import OnboardingFeature

@MainActor @Suite struct OnboardingModelTests {
    /// Feature spec §2: the ten steps in order, from install to ready.
    @Test func fullFlowFromInstallToReady() async throws {
        let app = await TestApp(signedIn: false, paired: false, ready: false, start: testDate(2026, 11, 10, 14, 0))
        let model = OnboardingModel(app: app.model)
        #expect(model.step == .welcome && !model.canGoBack)
        model.advance()
        #expect(model.step == .signIn)
        await model.signInWithApple()
        #expect(app.model.session?.userID == TestApp.me)
        #expect(model.step == .relationship && !model.canGoBack)
        #expect(model.relationship == .romantic && RelationshipType.availableAtLaunch == [.romantic])
        model.advance()
        #expect(model.step == .invite)
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
        #expect(model.startingMinutes == 30 && model.dailyMax == 60)
        await model.saveMinutes()
        #expect(model.step == .ready)
        #expect(model.readyLine.replacingOccurrences(of: "\u{202F}", with: " ") == "Protected time starts at 6:00 PM.")
        await model.finish()
        #expect(app.model.phase == .ready)
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
        #expect(app.model.session?.email == "sam@example.com" && model.step == .relationship)
    }

    @Test func progressIsRememberedAcrossLaunches() async {
        let app = await TestApp(paired: false, ready: false)
        let model = OnboardingModel(app: app.model)
        #expect(model.step == .relationship)
        model.advance()
        model.advance()
        #expect(model.step == .notifications)
        #expect(OnboardingModel(app: app.model).step == .notifications)
        model.back()
        #expect(OnboardingModel(app: app.model).step == .invite)
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
