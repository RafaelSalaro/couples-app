import XCTest

/// 2026-11-15 founder testing: the protected-time status opens the schedule (P28), signing
/// out and back in (P29, P30), and the returning-user wording on the sign-in screen.
final class AccountAndHomeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// P28: tapping the protected-time status on the home screen opens the schedule.
    @MainActor
    func testStatusOpensTheSchedule() {
        let app = XCUIApplication.launched(scenario: "paired", ["-phase", "protected", "-partner", "silent"])
        app.tap("home.status")
        app.waitFor("schedule.row")
    }

    /// P30 then P29: sign out from Settings (visible, with the explanation), then sign back in
    /// with the same Apple ID: no error, everything restored, onboarding skipped.
    @MainActor
    func testSignOutAndBackIn() {
        let app = XCUIApplication.launched(scenario: "paired", ["-phase", "protected", "-partner", "silent"])
        app.waitFor("home.myBalance")
        app.tap("place.us")
        app.tap("us.settings")
        XCTAssertTrue(app.waitFor("settings.emergency").exists) // emergency minutes next to the daily maximum
        app.tap("settings.signOut")
        app.waitForText("Protected time pauses on this phone until you sign back in. You stay paired with Ana")
        app.tap("settings.signOut.confirm")
        app.tap("onboarding.start")
        app.tap("signin.apple")
        // Straight back to the home scene: same pair and minutes, no onboarding steps.
        XCTAssertEqual(app.waitFor("home.partnerBalance", timeout: 15).label, "Ana: 30 min")
        XCTAssertFalse(app.element("pairing.invite").exists)
    }

    /// P29: "Already have an account? Sign in" sits under "Email me a link" and shows the
    /// returning-user wording.
    @MainActor
    func testReturningUserWording() {
        let app = XCUIApplication.launched(scenario: "fresh", ["-partner", "silent"])
        app.tap("onboarding.start")
        app.waitFor("signin.sendLink")
        app.tap("signin.returning")
        app.waitForText("Welcome back")
        XCTAssertTrue(app.element("signin.apple").exists && app.element("signin.email").exists)
    }
}
