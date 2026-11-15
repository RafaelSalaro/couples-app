import XCTest

/// WP-6 acceptance: pairing with two seeded users (the app user and the scripted partner, Ana).
final class PairingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The user invites; Ana accepts on her side; both are paired.
    @MainActor
    func testInviteAndPartnerAccepts() {
        let app = XCUIApplication.launched(scenario: "onboarded")
        app.tap("home.invite")
        app.tap("pairing.invite")
        // Three ways to invite: link, 6-character code, QR.
        let code = app.waitFor("pairing.code")
        XCTAssertEqual(code.label.replacingOccurrences(of: "Invite code ", with: "").replacingOccurrences(of: " ", with: "").count, 6)
        XCTAssertTrue(app.element("pairing.share").exists)
        // Ana accepts a moment later.
        app.waitFor("celebration.paired", timeout: 15)
        XCTAssertTrue(app.hasText("You're now paired with Ana."))
        app.tap("celebration.done")
        // Paired state on the home screen: both balances with the starting minutes.
        app.waitFor("home.partnerBalance")
        XCTAssertFalse(app.element("home.invite").exists)
    }

    /// The user joins with the 6-character code Ana shared.
    @MainActor
    func testJoinWithCode() {
        let app = XCUIApplication.launched(scenario: "onboarded", ["-partner", "silent"])
        app.tap("home.invite")
        let field = app.waitFor("pairing.codeField")
        field.tap()
        field.typeText("wrong1")
        app.tap("pairing.join")
        app.waitForText("That code didn't match")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        field.typeText("ana234")
        app.tap("pairing.join")
        app.waitFor("celebration.paired")
        app.tap("celebration.done")
    }

    /// Joining by scanning Ana's invite QR (the Simulator has no camera, so a sample code stands in).
    @MainActor
    func testJoinByScanning() {
        let app = XCUIApplication.launched(scenario: "onboarded", ["-partner", "silent"])
        app.tap("home.invite")
        app.tap("pairing.scan")
        app.tap("scanner.sample")
        app.waitFor("celebration.paired")
    }

    /// A universal invite link opens the app and pairs.
    @MainActor
    func testInviteLinkOpensTheApp() {
        let app = XCUIApplication.launched(scenario: "onboarded", ["-partner", "silent"])
        app.waitFor("home.invite")
        XCUIDevice.shared.system.open(URL(string: "couplesapp://invite/demoinvite")!)
        app.waitFor("celebration.paired", timeout: 15)
    }

    /// Unpair: one confirmation, instant, no approval from the partner.
    @MainActor
    func testUnpair() {
        let app = XCUIApplication.launched(scenario: "paired")
        app.waitFor("home.partnerBalance")
        app.tap("place.us")
        app.tap("us.partner")
        app.tap("partner.unpair")
        app.tap("partner.unpair.confirm")
        app.waitForText("You're no longer paired")
        app.tap("place.tonight")
        app.waitFor("home.invite")
    }

    /// When the partner ends the pairing the user gets a gentle note, with no reason.
    @MainActor
    func testPartnerUnpairs() {
        let app = XCUIApplication.launched(scenario: "paired", ["-partnerActions", "unpair"])
        app.waitForText("Ana ended your pairing.", timeout: 15)
        app.waitFor("home.invite")
    }
}
