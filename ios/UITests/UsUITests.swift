import XCTest

/// WP-10 and WP-12 acceptance: home, protected time, the week, settings, account deletion, the paywall.
final class UsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The home scene: both balances, the status with time left, the streak, unlock, today's activity.
    @MainActor
    func testHomeScene() {
        let app = XCUIApplication.launched(scenario: "paired", ["-phase", "protected", "-partner", "silent", "-streak", "7"])
        app.waitFor("home.ring.protected")
        XCTAssertEqual(app.waitFor("home.myBalance").label, "You: 30 min")
        XCTAssertEqual(app.element("home.partnerBalance").label, "Ana: 30 min")
        app.waitForText("of protected time left")
        app.waitForText("7 evenings in a row, together")
        XCTAssertTrue(app.element("home.unlock").exists)
        XCTAssertTrue(app.element("home.emergency").exists)
        app.waitForText("You two paired")
        // Outside protected time there is nothing to unlock, and the scene says when it starts.
        let open = XCUIApplication.launched(scenario: "paired", ["-phase", "open", "-partner", "silent"])
        open.waitFor("home.ring.open")
        open.waitForText("protected time starts")
        XCTAssertFalse(open.element("home.unlock").exists)
    }

    /// A streak milestone is celebrated once.
    @MainActor
    func testPartnerStatusIsNeutral() {
        let app = XCUIApplication.launched(scenario: "paired", ["-partnerActions", "turnProtectionOff"])
        app.waitFor("home.partnerOff", timeout: 15)
        app.waitForText("Protected time is off on Ana's phone.")
    }

    /// Longer protected time applies at once; shorter asks the partner, who approves.
    @MainActor
    func testScheduleEditorAndApproval() {
        let app = XCUIApplication.launched(scenario: "paired")
        app.tap("place.us")
        app.tap("us.schedule")
        app.tap("schedule.row")
        // Dropping a day makes protected time shorter: the partner is asked.
        app.tap("day.7")
        app.waitForText("Ana will be asked")
        app.tap("schedule.save")
        app.waitFor("schedule.saved")
        // Ana approves a moment later and the days change.
        app.waitForText("Mon, Tue, Wed, Thu, Fri, Sat", timeout: 15)
        // Adding the day back is stricter and applies right away.
        app.tap("schedule.row")
        app.tap("day.7")
        app.waitForText("This applies right away.")
        app.tap("schedule.save")
        app.waitForText("Every day")
    }

    /// The partner asks to shorten protected time; "Let's talk" keeps it as it is.
    @MainActor
    func testPartnersScheduleRequest() {
        let app = XCUIApplication.launched(scenario: "paired", ["-partnerActions", "proposeScheduleChange"])
        app.tap("place.us")
        app.tap("us.schedule")
        app.waitFor("change.question", timeout: 15)
        app.waitForText("Ana would like protected time to be")
        app.tap("change.talk")
        XCTAssertFalse(app.element("change.question").waitForExistence(timeout: 3))
    }

    /// Pausing fewer apps asks the partner, who is never told which apps.
    @MainActor
    func testPausedApps() {
        let app = XCUIApplication.launched(scenario: "paired", ["-partner", "silent"])
        app.tap("place.us")
        app.tap("us.schedule")
        app.tap("schedule.apps")
        app.tap("picker.category.games")
        app.waitForText("This applies right away.")
        app.tap("apps.save")
        app.waitForText("2 categories")
        app.tap("schedule.apps")
        app.tap("picker.category.social")
        app.waitForText("without seeing which apps")
        app.tap("apps.save")
        app.waitFor("change.waiting")
        app.waitForText("You asked to pause fewer apps.")
    }

    /// The weekly report: this week for free, with the private Screen Time report explained.
    @MainActor
    func testWeeklyReport() {
        let app = XCUIApplication.launched(scenario: "paired")
        app.tap("place.us")
        app.tap("us.week")
        app.waitFor("report.together")
        app.waitForText("This week")
        app.waitForText("Minutes earned")
        app.waitFor("report.premium")
        app.waitFor("report.private")
        app.waitForText("never leaves your phone")
    }

    /// Settings: notification categories (requests cannot be muted), email off by default, export.
    @MainActor
    func testSettings() {
        let app = XCUIApplication.launched(scenario: "paired")
        app.tap("place.us")
        app.tap("us.settings")
        app.waitFor("settings.name")
        XCTAssertFalse(app.waitFor("notify.unlock_request").isEnabled)
        XCTAssertTrue(app.element("notify.kudos").isEnabled)
        XCTAssertEqual(app.element("notify.email").value as? String, "0")
        app.tap("settings.export")
        app.waitFor("settings.exportShare")
        XCTAssertTrue(app.element("settings.safety").exists)
        XCTAssertTrue(app.element("settings.privacy").exists)
    }

    /// Account deletion in two steps; afterwards the app is back at the welcome screen.
    @MainActor
    func testDeleteAccount() {
        let app = XCUIApplication.launched(scenario: "paired")
        app.tap("place.us")
        app.tap("us.settings")
        app.tap("settings.delete")
        app.waitForText("You and Ana are unpaired right away.")
        app.waitForText("does not cancel an Apple subscription")
        app.tap("delete.continue")
        app.tap("delete.confirm")
        app.waitFor("onboarding.start", timeout: 15)
    }

    /// The paywall: one price for both, trial, and premium unlocking for the pair.
    @MainActor
    func testPaywallTrialPurchase() {
        let app = XCUIApplication.launched(scenario: "paired", ["-partner", "silent"])
        app.tap("place.together")
        app.tap("challenges.premium")
        XCTAssertEqual(app.waitFor("paywall.headline").label, "One price for both of you")
        app.waitForText("$39.99")
        app.waitForText("$119.99")
        XCTAssertEqual(app.waitFor("paywall.priceLine").label, "14 days free, then $39.99/year for both of you")
        app.tap("paywall.premium_lifetime")
        XCTAssertEqual(app.waitFor("paywall.priceLine").label, "$119.99 once, for both of you")
        app.tap("paywall.premium_yearly")
        app.tap("paywall.buy")
        app.waitFor("paywall.thanks")
        app.waitForText("Premium is on for you and Ana.")
        app.tap("paywall.done")
        // The library and custom challenges are now there.
        app.waitFor("custom.add")
        app.waitFor("challenge.Board game night")
    }

    /// Restore finds an earlier purchase; a cancelled purchase is not an error.
    @MainActor
    func testRestoreAndCancel() {
        let app = XCUIApplication.launched(scenario: "paired", ["-partner", "silent", "-purchase", "cancel", "-restorable", "1"])
        app.tap("place.us")
        app.tap("us.settings")
        app.tap("settings.subscription")
        app.tap("paywall.buy")
        XCTAssertFalse(app.element("paywall.message").waitForExistence(timeout: 2))
        app.tap("paywall.restore")
        app.waitFor("paywall.thanks")
    }
}
