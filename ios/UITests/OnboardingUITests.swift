import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// WP-5 acceptance: install → ready, through all ten steps of feature spec §2.
    @MainActor
    func testInstallToReady() {
        let app = XCUIApplication.launched(scenario: "fresh", ["-partner", "silent"])
        app.waitForText("Not about control. About being here, together.")
        app.tap("onboarding.start")
        app.tap("signin.apple")
        // Apple shared the name, so no name step; no relationship step either (P3, P27).
        // Invite or join: continue alone for now.
        app.waitFor("pairing.invite")
        app.tap("onboarding.next")
        // Notifications, with the reason.
        app.waitForText("So your partner's requests and kudos reach you.")
        app.tap("onboarding.next")
        // Screen Time permission.
        app.tap("onboarding.next")
        // Choose paused apps: guidance first, nothing pre-selected.
        app.waitForText("Tap Social")
        XCTAssertFalse(app.element("onboarding.next").isEnabled)
        app.tap("picker.category.social")
        app.tap("onboarding.next")
        // Protected time (default 6 PM–9 AM).
        app.waitFor("schedule.start")
        app.tap("onboarding.next")
        // Starting minutes and daily maximum.
        app.waitFor("minutes.starting")
        app.waitForText("30 min")
        app.waitForText("60 min")
        app.tap("onboarding.next")
        app.waitFor("ready.line")
        XCTAssertTrue(app.hasText("Protected time"))
        app.tap("onboarding.done")
        app.waitFor("home.screen")
        // Before the partner joins the app is in "waiting for your partner" mode.
        app.waitFor("home.invite")
    }

    @MainActor
    func testMagicLinkSignIn() {
        let app = XCUIApplication.launched(scenario: "fresh", ["-partner", "silent"])
        app.tap("onboarding.start")
        let field = app.waitFor("signin.email")
        field.tap()
        field.typeText("sam@example.com")
        app.tap("signin.sendLink")
        app.waitFor("signin.sent")
        app.tap("signin.demoLink")
        // Email never provides a name: "What should we call you?" right after sign-in (P27).
        let name = app.waitFor("name.field")
        name.tap()
        XCTAssertFalse(app.element("onboarding.next").isEnabled) // required
        name.typeText("Sam")
        app.tap("onboarding.next")
        app.waitFor("pairing.invite")
    }

    @MainActor
    func testDecliningScreenTimeIsGentle() {
        let app = XCUIApplication.launched(scenario: "fresh", ["-partner", "silent", "-screenTime", "deny"])
        app.tap("onboarding.start")
        app.tap("signin.apple")
        app.tap("onboarding.next") // continue alone
        app.tap("onboarding.skip") // notifications: not now
        app.tap("onboarding.next") // Screen Time: declined
        app.waitFor("screentime.declined")
        app.tap("onboarding.skip")
        app.waitFor("schedule.start") // the picker is skipped
        app.tap("onboarding.next")
        app.tap("onboarding.next")
        app.tap("onboarding.done")
        // Home offers to turn it on, without blame.
        app.waitFor("home.reenable")
    }
}
