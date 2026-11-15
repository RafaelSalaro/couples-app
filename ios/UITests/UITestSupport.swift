import XCTest

/// UI tests drive the real app on the in-memory backend and `MockBlockingService`
/// (see `LaunchOptions` in the app target for the launch arguments).
extension XCUIApplication {
    static func launched(scenario: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTest", "1", "-scenario", scenario] + extra
        app.launch()
        return app
    }

    /// Any element with this accessibility identifier.
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @discardableResult
    func waitFor(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = element(identifier)
        let exists = found.waitForExistence(timeout: timeout)
        if !exists {
            XCUIApplication.saveFailureScreenshot(named: identifier)
            // The element tree shows what was on screen instead, straight in the test log.
            print("UI-FAIL \(identifier) — screen was:\n\(debugDescription)")
        }
        XCTAssertTrue(exists, "Missing \(identifier)", file: file, line: line)
        return found
    }

    func tap(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let found = waitFor(identifier, timeout: timeout, file: file, line: line)
        if !found.isHittable { swipeUp() }
        found.tap()
    }

    func waitForText(_ text: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let found = descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "Missing text “\(text)”", file: file, line: line)
    }

    /// When `UI_FAIL_DIR` is set (pass `TEST_RUNNER_UI_FAIL_DIR=<folder>` to xcodebuild), a failed
    /// wait leaves a screenshot there, which is the quickest way to see what the screen showed.
    static func saveFailureScreenshot(named name: String) {
        guard let folder = ProcessInfo.processInfo.environment["UI_FAIL_DIR"] else { return }
        let safe = name.replacingOccurrences(of: "/", with: "_")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(safe).png"))
    }

    func hasText(_ text: String) -> Bool {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch.exists
    }
}
