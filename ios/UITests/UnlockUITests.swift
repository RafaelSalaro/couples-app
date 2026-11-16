import XCTest

/// WP-7 and WP-8 acceptance: the mock blocking flows, and each unlock method.
final class UnlockUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launchProtected(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.launched(scenario: "paired", ["-phase", "protected"] + extra)
        app.waitFor("home.ring.protected")
        return app
    }

    /// The simulated pause screen: "Ask Ana" leads to the unlock sheet, as the notification does on a real phone.
    @MainActor
    func testPauseScreenLeadsToTheUnlockSheet() {
        let app = launchProtected(["-partner", "silent"])
        app.tap("home.previewShield")
        app.waitForText("Protected time")
        XCTAssertEqual(app.waitFor("shield.primary").label, "Ask Ana")
        XCTAssertEqual(app.element("shield.secondary").label, "Not now")
        app.tap("shield.primary")
        app.waitFor("unlock.method.ask")
        // All four ways are there, the emergency unlock among them.
        XCTAssertTrue(app.element("unlock.method.scan").exists)
        XCTAssertTrue(app.element("unlock.method.minutes").exists)
        XCTAssertTrue(app.element("unlock.method.emergency").exists)
    }

    /// Ask your partner: Ana says "Go for it" and the unlock starts.
    @MainActor
    func testAskPartnerGoForIt() {
        let app = launchProtected()
        app.tap("home.unlock")
        app.tap("unlock.length.15")
        app.tap("unlock.method.ask")
        app.tap("ask.send")
        app.waitFor("unlock.started", timeout: 15)
        app.tap("unlock.done")
        app.waitFor("home.ring.unlocked")
        // No minutes were spent.
        XCTAssertEqual(app.element("home.myBalance").label, "You: 30 min")
    }

    /// "Let's wait" is a calm note, never a red state.
    @MainActor
    func testAskPartnerLetsWait() {
        let app = launchProtected(["-partner", "no"])
        app.tap("home.unlock")
        app.tap("unlock.method.ask")
        app.tap("ask.send")
        let outcome = app.waitFor("ask.outcome", timeout: 15)
        XCTAssertEqual(outcome.label, "Ana says let's wait — maybe later?")
        XCTAssertTrue(app.element("ask.again").exists)
    }

    /// Email fallback: with the partner's notifications off the 6-digit code can be typed in.
    @MainActor
    func testAccountabilityCode() {
        let app = launchProtected(["-partner", "silent", "-partnerPushOff", "1"])
        app.tap("home.unlock")
        app.tap("unlock.method.ask")
        app.tap("ask.send")
        app.waitFor("ask.waiting")
        let field = app.waitFor("ask.code")
        field.tap()
        field.typeText("246810")
        app.tap("ask.redeem")
        app.waitFor("unlock.started")
    }

    /// In-person QR: scanning the partner's rotating code (a sample stands in for the camera).
    @MainActor
    func testScanPartnerCode() {
        let app = launchProtected(["-partner", "silent"])
        app.tap("home.unlock")
        app.tap("unlock.method.scan")
        app.tap("scanner.sample")
        app.waitFor("unlock.started")
        app.tap("unlock.done")
        app.waitFor("home.ring.unlocked")
        // "Show my code" has the rotating QR.
        app.tap("home.showCode")
        app.waitFor("code.qr")
        app.tap("code.done")
    }

    /// Minutes: spend from the balance; the unlock can be ended early.
    @MainActor
    func testUseMinutes() {
        let app = launchProtected(["-partner", "silent"])
        app.tap("home.unlock")
        app.tap("unlock.length.60")
        app.tap("unlock.method.minutes")
        // 60 minutes with a balance of 30: explained, not possible.
        XCTAssertFalse(app.waitFor("minutes.spend").isEnabled)
        app.navigationBars.buttons.firstMatch.tap()
        app.tap("unlock.length.15")
        app.tap("unlock.method.minutes")
        app.tap("minutes.spend")
        app.waitFor("unlock.started")
        app.tap("unlock.done")
        XCTAssertEqual(app.waitFor("home.myBalance").label, "You: 15 min")
        // Ending early asks first and says the unused minutes come back (P26).
        app.tap("home.endUnlock")
        app.waitForText("go back to your balance")
        app.tap("home.endUnlock.confirm")
        app.waitFor("home.ring.protected")
        XCTAssertEqual(app.waitFor("home.myBalance").label, "You: 29 min") // 1 minute counted as used
    }

    /// Emergency unlock: always available, even alone with zero minutes; once a week; balance goes negative.
    @MainActor
    func testEmergencyUnlockWithoutPartner() {
        let app = XCUIApplication.launched(scenario: "onboarded", ["-phase", "protected", "-partner", "silent"])
        app.waitFor("home.ring.protected")
        app.tap("home.emergency")
        // Partner methods say what is missing.
        XCTAssertFalse(app.waitFor("unlock.method.ask").isEnabled)
        app.tap("unlock.method.emergency")
        app.waitForText("15 min of your 15 min emergency minutes left this week")
        app.tap("emergency.use")
        app.waitFor("unlock.started")
        app.tap("unlock.done")
        // Nothing is borrowed while it runs (P14).
        XCTAssertEqual(app.waitFor("home.myBalance").label, "You: 0 min")
        // Ending early: a confirmation says what stays available, then only the minute used is borrowed.
        app.tap("home.endUnlock")
        app.waitForText("of your 15 min emergency minutes this week")
        app.tap("home.endUnlock.confirm")
        let balance = app.waitFor("home.myBalance")
        expectation(for: NSPredicate(format: "label == %@", "You: -1 min"), evaluatedWith: balance)
        waitForExpectations(timeout: 10)
        app.tap("home.emergency")
        app.waitForText("14 min of your 15 min emergency minutes left this week")
        XCTAssertTrue(app.element("unlock.method.emergency").isEnabled)
    }

    /// The partner asks; the user answers "Go for it" from the request card.
    @MainActor
    func testIncomingRequest() {
        let app = XCUIApplication.launched(scenario: "paired", ["-phase", "protected", "-partnerActions", "askUnlock"])
        let title = app.waitFor("request.title", timeout: 15)
        XCTAssertEqual(title.label, "Ana asks for 30 min")
        app.waitForText("Reply to a client")
        app.tap("request.approve")
        app.waitFor("home.screen")
        XCTAssertFalse(app.element("request.title").waitForExistence(timeout: 2))
    }
}
