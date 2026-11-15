import Backend
import Core
import FeatureSupport
import Foundation
import Observation

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// The weekly report (feature spec §10): individual numbers side by side, combined numbers,
/// highlights. Free shows this week's summary; premium adds history, charts and highlights.
/// Only things the app itself creates; never app usage.
@MainActor @Observable
public final class ReportsModel {
    /// One side-by-side line of the report.
    public struct Row: Identifiable, Equatable {
        public var id: String
        public var title: String
        public var mine: Int
        public var theirs: Int
        public var isMinutes: Bool
    }

    public let app: AppModel
    public private(set) var reports: [WeeklyReport] = []
    public private(set) var loaded = false
    public var selectedWeek: LocalDay?

    public init(app: AppModel) { self.app = app }

    public func load() async {
        if let value = try? await app.deps.backend.fetchWeeklyReports() { reports = value }
        loaded = true
    }

    public var isPremium: Bool { app.isPremium }
    public var current: WeeklyReport? { reports.first }
    /// The report on screen: the chosen past week (premium), else this week.
    public var shown: WeeklyReport? {
        guard isPremium, let selectedWeek else { return current }
        return reports.first { $0.weekStart == selectedWeek } ?? current
    }
    /// Past weeks: full history is premium.
    public var history: [WeeklyReport] { isPremium ? Array(reports.dropFirst()) : [] }
    public var hasLockedHistory: Bool { !isPremium }

    public func weekTitle(_ report: WeeklyReport, locale: Locale = .current) -> String {
        if report.weekStart == current?.weekStart { return L("This week") }
        let calendar = Calendar.gregorian(in: app.deps.timeZone())
        var format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        format.locale = locale
        format.timeZone = app.deps.timeZone()
        return L("Week of \(report.weekStart.startDate(calendar: calendar).formatted(format))")
    }

    public func rows(_ report: WeeklyReport) -> [Row] {
        guard let me = app.myID else { return [] }
        let mine = report.stats(for: me)
        let theirs = app.pair.map { report.stats(for: $0.partner.id) } ?? WeeklyMemberStats()
        return [
            Row(id: "earned", title: L("Minutes earned"), mine: mine.minutesEarned, theirs: theirs.minutesEarned, isMinutes: true),
            Row(id: "spent", title: L("Minutes spent"), mine: mine.minutesSpent, theirs: theirs.minutesSpent, isMinutes: true),
            Row(id: "expired", title: L("Minutes expired"), mine: mine.minutesExpired, theirs: theirs.minutesExpired, isMinutes: true),
            Row(id: "challenges", title: L("Challenges completed"), mine: mine.challengesCompleted, theirs: theirs.challengesCompleted, isMinutes: false),
            Row(id: "requests", title: L("Requests sent"), mine: mine.requestsSent, theirs: theirs.requestsSent, isMinutes: false),
            Row(id: "approved", title: L("Requests approved"), mine: mine.requestsApproved, theirs: theirs.requestsApproved, isMinutes: false),
            Row(id: "kudosGiven", title: L("Kudos given"), mine: mine.kudosGiven, theirs: theirs.kudosGiven, isMinutes: false),
            Row(id: "kudosReceived", title: L("Kudos received"), mine: mine.kudosReceived, theirs: theirs.kudosReceived, isMinutes: false),
        ]
    }

    public func value(_ row: Row, mine: Bool) -> String {
        let number = mine ? row.mine : row.theirs
        return row.isMinutes ? MinutesText.short(number) : number.formatted()
    }

    /// Share of a row that is this person's, for the two-light comparison bar (0.5 when both are zero).
    public func share(_ row: Row) -> Double {
        let total = row.mine + row.theirs
        return total == 0 ? 0.5 : Double(row.mine) / Double(total)
    }

    public func combined(_ report: WeeklyReport) -> [(title: String, value: String)] {
        [
            (L("Earned together"), MinutesText.short(report.totalEarnedTogether)),
            (L("Shared challenges"), report.sharedChallengesDone.formatted()),
            (L("Protected hours"), report.protectedHours.formatted()),
            (L("Streak"), report.streak.formatted()),
        ]
    }

    /// "Most generous: Ana gave 4 kudos this week." Always a celebration, never a ranking of shortcomings.
    public func highlights(_ report: WeeklyReport) -> [String] {
        guard isPremium else { return [] }
        var lines: [String] = []
        if let id = report.mostGenerousUserID {
            let given = report.stats(for: id).kudosGiven
            let kudos = given == 1 ? L("1 kudos") : L("\(given.formatted()) kudos")
            lines.append(id == app.myID
                ? L("Most generous: you gave \(kudos) this week.")
                : L("Most generous: \(app.partnerName ?? "") gave \(kudos) this week."))
        }
        if report.sharedChallengesDone > 0 {
            lines.append(report.sharedChallengesDone == 1
                ? L("You did 1 challenge together.")
                : L("You did \(report.sharedChallengesDone.formatted()) challenges together."))
        }
        if report.streak > 0, Streak.milestones.contains(report.streak) {
            lines.append(L("\(report.streak.formatted()) evenings in a row. That's a milestone."))
        }
        return lines
    }

    /// Minutes earned together per week, oldest first, for the history chart (premium).
    public var trend: [(week: WeeklyReport, fraction: Double)] {
        let weeks = Array(reports.prefix(8).reversed())
        let top = weeks.map(\.totalEarnedTogether).max() ?? 0
        return weeks.map { ($0, top == 0 ? 0 : Double($0.totalEarnedTogether) / Double(top)) }
    }
}
