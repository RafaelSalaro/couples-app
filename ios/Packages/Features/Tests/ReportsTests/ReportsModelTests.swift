import Backend
import Core
import FeatureSupport
import FeatureTestSupport
import Foundation
import Testing
@testable import ReportsFeature

@MainActor @Suite struct ReportsModelTests {
    func seededWeek(_ app: TestApp) async throws {
        let challenge = try #require(try await app.backend.fetchChallenges().first { $0.isShared })
        let completion = try await app.backend.completeChallenge(id: challenge.id, note: nil)
        try await app.partner.confirmCompletion(id: completion.id)
        let request = try await app.backend.createUnlockRequest(minutes: 30, reason: nil)
        try await app.partner.respondUnlockRequest(id: request.id, approve: true)
        _ = try await app.backend.spendMinutesUnlock(minutes: 15, clientEventID: UUID())
    }

    func past(_ app: TestApp) {
        let pair = try? app.world.pairState(TestApp.me)?.pair.id
        guard let pair else { return }
        app.world.seedPastReports(for: pair, [
            WeeklyReport(weekStart: LocalDay(year: 2026, month: 11, day: 2), totalEarnedTogether: 120, sharedChallengesDone: 3, protectedHours: 190, streak: 7),
            WeeklyReport(weekStart: LocalDay(year: 2026, month: 10, day: 26), totalEarnedTogether: 60, sharedChallengesDone: 1, protectedHours: 200, streak: 2),
        ])
    }

    @Test func thisWeekSideBySideAndCombined() async throws {
        let app = await TestApp()
        try await seededWeek(app)
        let model = ReportsModel(app: app.model)
        await model.load()
        let report = try #require(model.shown)
        #expect(model.weekTitle(report) == "This week")
        let rows = model.rows(report)
        #expect(rows.map(\.id) == ["earned", "spent", "expired", "challenges", "requests", "approved", "kudosGiven", "kudosReceived"])
        #expect(rows[0].mine == 20 && rows[0].theirs == 20)
        #expect(model.value(rows[1], mine: true) == "15 min" && model.value(rows[1], mine: false) == "0 min")
        #expect(model.value(rows[3], mine: true) == "1" && rows[4].mine == 1 && rows[5].mine == 1)
        #expect(model.share(rows[1]) == 1 && model.share(rows[2]) == 0.5)
        let combined = model.combined(report)
        #expect(combined.map(\.value) == ["40 min", "1", combined[2].value, "4"])
    }

    /// Feature spec §12: free shows this week's summary; history, charts and highlights are premium.
    @Test func freeTierIsThisWeekOnly() async throws {
        let app = await TestApp()
        past(app)
        try await seededWeek(app)
        let model = ReportsModel(app: app.model)
        await model.load()
        #expect(model.history.isEmpty && model.hasLockedHistory)
        #expect(model.highlights(try #require(model.shown)).isEmpty)
        model.selectedWeek = LocalDay(year: 2026, month: 11, day: 2)
        #expect(model.shown?.weekStart == LocalDay(year: 2026, month: 11, day: 9)) // still this week
    }

    @Test func premiumHasHistoryHighlightsAndTrend() async throws {
        let app = await TestApp(premium: true)
        past(app)
        try await seededWeek(app)
        _ = try await app.partner.giveKudos(minutes: 10, message: "", challengeID: nil)
        _ = try await app.partner.giveKudos(minutes: 5, message: "", challengeID: nil)
        let model = ReportsModel(app: app.model)
        await model.load()
        #expect(model.history.count == 2 && !model.hasLockedHistory)
        let lines = model.highlights(try #require(model.shown))
        #expect(lines.contains("Most generous: Ana gave 2 kudos this week."))
        #expect(lines.contains("You did 1 challenge together."))
        model.selectedWeek = LocalDay(year: 2026, month: 11, day: 2)
        let earlier = try #require(model.shown)
        #expect(model.weekTitle(earlier, locale: Locale(identifier: "en_US")) == "Week of Nov 2")
        #expect(model.highlights(earlier).contains("7 evenings in a row. That's a milestone."))
        let trend = model.trend
        #expect(trend.map(\.week.totalEarnedTogether) == [60, 120, 55]) // oldest first
        #expect(trend[1].fraction == 1 && trend[0].fraction == 0.5)
    }

    @Test func unpairedHasNoReport() async {
        let app = await TestApp(paired: false)
        let model = ReportsModel(app: app.model)
        await model.load()
        #expect(model.shown == nil && model.loaded)
    }
}
