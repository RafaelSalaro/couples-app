import XCTest

/// WP-9 acceptance: minutes, challenges and kudos.
final class TogetherUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Mark a challenge done; Ana confirms; the minutes arrive.
    @MainActor
    func testChallengeDoneAndConfirmed() {
        let app = XCUIApplication.launched(scenario: "paired")
        app.tap("place.together")
        app.waitFor("challenges.screen")
        app.tap("challenge.Write your partner a note")
        app.tap("challenge.done")
        app.waitFor("challenge.sent")
        app.tap("place.tonight")
        // 30 starting minutes + 10 once Ana confirms.
        let balance = app.waitFor("home.myBalance")
        let arrived = NSPredicate(format: "label == %@", "You: 40 min")
        expectation(for: arrived, evaluatedWith: balance)
        waitForExpectations(timeout: 15)
    }

    /// The partner did a challenge; the user confirms with one tap.
    @MainActor
    func testConfirmPartnersChallenge() {
        let app = XCUIApplication.launched(scenario: "paired", ["-partnerActions", "completeChallenge"])
        app.tap("place.together")
        app.tap("completion.confirm", timeout: 15)
        XCTAssertFalse(app.element("completion.confirm").waitForExistence(timeout: 3))
    }

    /// Free tier: five presets, the library and kudos are offered as premium without pressure.
    @MainActor
    func testFreeTierPreview() {
        let app = XCUIApplication.launched(scenario: "paired")
        app.tap("place.together")
        app.waitFor("challenge.Phone-free dinner together")
        app.waitFor("challenges.premium")
        app.tap("together.kudos")
        app.waitFor("kudos.premium")
    }

    /// Premium: give kudos; a custom challenge needs Ana's agreement on the value.
    @MainActor
    func testGiveKudosAndCustomChallenge() {
        let app = XCUIApplication.launched(scenario: "paired", ["-premium", "1"])
        app.tap("place.together")
        app.tap("together.kudos")
        app.tap("kudos.amount.15")
        app.tap("kudos.give")
        app.waitFor("kudos.sent")
        app.waitForText("Ana just got 15 min from you.")
        app.tap("kudos.done")
        app.tap("custom.add")
        let title = app.waitFor("custom.title")
        title.tap()
        title.typeText("Fix the bike together")
        app.tap("custom.send")
        // Ana agrees a moment later and the challenge joins the list.
        app.waitFor("challenge.Fix the bike together", timeout: 15)
    }

    /// Kudos received: the celebration, and the minutes on the home scene.
    @MainActor
    func testKudosReceivedCelebration() {
        let app = XCUIApplication.launched(scenario: "paired", ["-premium", "1", "-partnerActions", "sendKudos"])
        app.waitFor("celebration.kudos", timeout: 15)
        app.waitForText("Kudos from Ana")
        app.waitForText("You made me laugh today")
        XCTAssertEqual(app.element("kudos.amount").label, "+10 min")
        app.tap("kudos.done")
        XCTAssertEqual(app.waitFor("home.myBalance").label, "You: 40 min")
    }

    /// Minutes: balances, the expiration timeline, history and a mutual reset.
    @MainActor
    func testMinutesScreenAndReset() {
        let app = XCUIApplication.launched(scenario: "paired")
        app.tap("place.us")
        app.tap("us.minutes")
        app.waitFor("minutes.chart")
        app.waitForText("30 min expire")
        app.waitFor("minutes.history")
        app.tap("reset.propose")
        // Ana agrees; both balances are reset to the standard amount and the proposal is gone.
        app.waitFor("reset.propose", timeout: 15)
        app.waitForText("Fresh start")
    }

    /// A reset the partner proposed needs this person's agreement.
    @MainActor
    func testIncomingReset() {
        let app = XCUIApplication.launched(scenario: "paired", ["-partnerActions", "proposeReset"])
        app.tap("place.us")
        app.tap("us.minutes")
        app.waitFor("reset.incoming", timeout: 15)
        app.tap("reset.accept")
        app.waitFor("reset.propose")
    }
}
