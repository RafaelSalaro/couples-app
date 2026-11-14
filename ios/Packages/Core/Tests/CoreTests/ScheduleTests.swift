import Foundation
import Testing
@testable import Core

let newYork = TimeZone(identifier: "America/New_York")!
let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!

/// A local wall-clock date in a time zone.
func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, in zone: TimeZone = newYork) -> Date {
    Calendar.gregorian(in: zone).date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

@Suite struct ScheduleEvaluatorTests {
    let evaluator = ScheduleEvaluator(timeZone: newYork)
    let standard = [ProtectedSchedule.standard()]

    @Test func defaultScheduleIsSixToNineEveryDay() {
        let s = ProtectedSchedule.standard()
        #expect(s.startLocal == LocalTime(hour: 18) && s.endLocal == LocalTime(hour: 9))
        #expect(s.weekdays == Set(1...7) && s.enabled && s.crossesMidnight)
        #expect(s.lengthMinutes == 15 * 60)
    }

    /// 07 §3: 18:00–09:00 is protected at 23:00, 02:00, 08:59 and not at 09:00 or 17:59.
    @Test func overnightScheduleBoundaries() {
        #expect(evaluator.isProtected(at: local(2026, 11, 10, 23, 0), schedules: standard))
        #expect(evaluator.isProtected(at: local(2026, 11, 11, 2, 0), schedules: standard))
        #expect(evaluator.isProtected(at: local(2026, 11, 11, 8, 59), schedules: standard))
        #expect(!evaluator.isProtected(at: local(2026, 11, 11, 9, 0), schedules: standard))
        #expect(!evaluator.isProtected(at: local(2026, 11, 11, 17, 59), schedules: standard))
        #expect(evaluator.isProtected(at: local(2026, 11, 11, 18, 0), schedules: standard))
    }

    @Test func currentProtectionAndNextStart() {
        let at = local(2026, 11, 11, 2, 0)
        let interval = evaluator.currentProtection(at: at, schedules: standard)
        #expect(interval?.start == local(2026, 11, 10, 18))
        #expect(interval?.end == local(2026, 11, 11, 9))
        #expect(evaluator.currentProtection(at: local(2026, 11, 11, 12), schedules: standard) == nil)
        #expect(evaluator.nextStart(after: local(2026, 11, 11, 12), schedules: standard) == local(2026, 11, 11, 18))
        #expect(evaluator.nextStart(after: local(2026, 11, 11, 18), schedules: standard) == local(2026, 11, 12, 18))
    }

    /// Device script 9: 23:50–00:20 protects through midnight.
    @Test func shortMidnightCrossing() {
        let s = [ProtectedSchedule(startLocal: LocalTime(hour: 23, minute: 50), endLocal: LocalTime(hour: 0, minute: 20))]
        #expect(evaluator.isProtected(at: local(2026, 11, 10, 23, 55), schedules: s))
        #expect(evaluator.isProtected(at: local(2026, 11, 11, 0, 0), schedules: s))
        #expect(evaluator.isProtected(at: local(2026, 11, 11, 0, 19), schedules: s))
        #expect(!evaluator.isProtected(at: local(2026, 11, 11, 0, 20), schedules: s))
        #expect(!evaluator.isProtected(at: local(2026, 11, 10, 23, 49), schedules: s))
    }

    @Test func weekdaysAreStartDays() {
        // Friday and Saturday nights only (5, 6): Saturday 02:00 and Sunday 02:00 are protected, Monday 02:00 is not.
        let s = [ProtectedSchedule(weekdays: [5, 6], startLocal: LocalTime(hour: 22), endLocal: LocalTime(hour: 6))]
        #expect(evaluator.isProtected(at: local(2026, 11, 13, 23), schedules: s)) // Friday
        #expect(evaluator.isProtected(at: local(2026, 11, 14, 2), schedules: s)) // Saturday early (Friday's)
        #expect(evaluator.isProtected(at: local(2026, 11, 15, 2), schedules: s)) // Sunday early (Saturday's)
        #expect(!evaluator.isProtected(at: local(2026, 11, 15, 23), schedules: s)) // Sunday night
        #expect(!evaluator.isProtected(at: local(2026, 11, 16, 2), schedules: s)) // Monday early
        #expect(evaluator.nextStart(after: local(2026, 11, 16, 2), schedules: s) == local(2026, 11, 20, 22))
    }

    @Test func disabledOrEmptySchedulesNeverProtect() {
        var s = ProtectedSchedule.standard()
        s.enabled = false
        #expect(!evaluator.isProtected(at: local(2026, 11, 10, 23), schedules: [s]))
        #expect(!evaluator.isProtected(at: local(2026, 11, 10, 23), schedules: []))
        #expect(evaluator.nextStart(after: local(2026, 11, 10, 23), schedules: [s]) == nil)
    }

    @Test func daytimeScheduleAndMultipleSchedulesMerge() {
        let day = ProtectedSchedule(startLocal: LocalTime(hour: 9), endLocal: LocalTime(hour: 12))
        #expect(evaluator.isProtected(at: local(2026, 11, 10, 9), schedules: [day]))
        #expect(!evaluator.isProtected(at: local(2026, 11, 10, 12), schedules: [day]))
        // Standard ends at 09:00 exactly when the daytime one starts: one continuous stretch to noon.
        let merged = evaluator.currentProtection(at: local(2026, 11, 10, 8), schedules: standard + [day])
        #expect(merged?.end == local(2026, 11, 10, 12))
        #expect(merged?.start == local(2026, 11, 9, 18))
    }

    @Test func equalStartAndEndMeansAllDay() {
        let s = [ProtectedSchedule(startLocal: LocalTime(hour: 8), endLocal: LocalTime(hour: 8))]
        #expect(evaluator.isProtected(at: local(2026, 11, 10, 7, 59), schedules: s))
        #expect(evaluator.isProtected(at: local(2026, 11, 10, 8), schedules: s))
    }

    /// 07 §3: daylight-saving transition days. US clocks spring forward on 2026-03-08 and fall back on 2026-11-01.
    @Test func springForwardNight() {
        // 02:00–03:00 does not exist on March 8. The night is one hour shorter but the boundaries hold.
        #expect(evaluator.isProtected(at: local(2026, 3, 7, 23), schedules: standard))
        #expect(evaluator.isProtected(at: local(2026, 3, 8, 3, 30), schedules: standard))
        #expect(evaluator.isProtected(at: local(2026, 3, 8, 8, 59), schedules: standard))
        #expect(!evaluator.isProtected(at: local(2026, 3, 8, 9, 0), schedules: standard))
        let interval = evaluator.currentProtection(at: local(2026, 3, 8, 4), schedules: standard)
        #expect(interval?.duration == TimeInterval(14 * 3600))
    }

    @Test func fallBackNight() {
        #expect(evaluator.isProtected(at: local(2026, 10, 31, 23), schedules: standard))
        #expect(evaluator.isProtected(at: local(2026, 11, 1, 8, 59), schedules: standard))
        #expect(!evaluator.isProtected(at: local(2026, 11, 1, 9, 0), schedules: standard))
        let interval = evaluator.currentProtection(at: local(2026, 11, 1, 4), schedules: standard)
        #expect(interval?.duration == TimeInterval(16 * 3600))
        // Both passes through the repeated 01:30 are protected.
        let firstPass = local(2026, 11, 1, 0, 30).addingTimeInterval(3600)
        #expect(evaluator.isProtected(at: firstPass, schedules: standard))
        #expect(evaluator.isProtected(at: firstPass.addingTimeInterval(3600), schedules: standard))
    }

    @Test func scheduleStartingInsideTheSkippedHour() {
        // 02:30 does not exist on March 8; the schedule still starts (shifted) and ends at 05:00.
        let s = [ProtectedSchedule(startLocal: LocalTime(hour: 2, minute: 30), endLocal: LocalTime(hour: 5))]
        #expect(evaluator.isProtected(at: local(2026, 3, 8, 4), schedules: s))
        #expect(!evaluator.isProtected(at: local(2026, 3, 8, 5), schedules: s))
        #expect(!evaluator.isProtected(at: local(2026, 3, 8, 1, 59), schedules: s))
    }

    @Test func evaluatesInTheGivenTimeZone() {
        // The same instant is protected in New York (19:00) and not in Los Angeles (16:00).
        let instant = local(2026, 11, 10, 19, 0)
        let la = ScheduleEvaluator(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(evaluator.isProtected(at: instant, schedules: standard))
        #expect(!la.isProtected(at: instant, schedules: standard))
    }
}

@Suite struct ScheduleChangeTests {
    let base = ProtectedSchedule.standard()

    func with(_ edit: (inout ProtectedSchedule) -> Void) -> [ProtectedSchedule] {
        var s = base
        edit(&s)
        return [s]
    }

    @Test func extendingHoursIsStricter() {
        #expect(ScheduleChange.classify(from: [base], to: with { $0.startLocal = LocalTime(hour: 17) }) == .stricter)
        #expect(ScheduleChange.classify(from: [base], to: with { $0.endLocal = LocalTime(hour: 10) }) == .stricter)
    }

    @Test func shorteningHoursIsLooser() {
        #expect(ScheduleChange.classify(from: [base], to: with { $0.startLocal = LocalTime(hour: 19) }) == .looser)
        #expect(ScheduleChange.classify(from: [base], to: with { $0.endLocal = LocalTime(hour: 8) }) == .looser)
    }

    @Test func daysAndOnOff() {
        let weekdaysOnly = with { $0.weekdays = [1, 2, 3, 4, 5] }
        #expect(ScheduleChange.classify(from: [base], to: weekdaysOnly) == .looser)
        #expect(ScheduleChange.classify(from: weekdaysOnly, to: [base]) == .stricter)
        #expect(ScheduleChange.classify(from: [base], to: with { $0.enabled = false }) == .looser)
        #expect(ScheduleChange.classify(from: with { $0.enabled = false }, to: [base]) == .stricter)
        #expect(ScheduleChange.classify(from: [base], to: []) == .looser)
    }

    @Test func shiftingIsLooserBecauseSomeTimeIsLost() {
        let shifted = with { $0.startLocal = LocalTime(hour: 19); $0.endLocal = LocalTime(hour: 10) }
        #expect(ScheduleChange.classify(from: [base], to: shifted) == .looser)
    }

    @Test func renamingOrAddingASecondScheduleIsNotLooser() {
        #expect(ScheduleChange.classify(from: [base], to: with { $0.name = "Evenings" }) == .same)
        let lunch = ProtectedSchedule(startLocal: LocalTime(hour: 12), endLocal: LocalTime(hour: 13))
        #expect(ScheduleChange.classify(from: [base], to: [base, lunch]) == .stricter)
        #expect(ScheduleChange.classify(from: [base, lunch], to: [base]) == .looser)
    }

    @Test func sundayNightWrapsIntoMonday() {
        let sunday = ProtectedSchedule(weekdays: [7], startLocal: LocalTime(hour: 22), endLocal: LocalTime(hour: 6))
        let coverage = ScheduleChange.coverage([sunday])
        #expect(coverage[0]) // Monday 00:00
        #expect(coverage[6 * 1440 + 22 * 60])
        #expect(!coverage[6 * 60])
    }

    /// 07 §3: stricter applies immediately; looser waits for approval; unpaired applies directly.
    @Test func whoNeedsApproval() {
        #expect(ScheduleChange.appliesImmediately(.stricter, isPaired: true))
        #expect(ScheduleChange.appliesImmediately(.same, isPaired: true))
        #expect(!ScheduleChange.appliesImmediately(.looser, isPaired: true))
        #expect(ScheduleChange.appliesImmediately(.looser, isPaired: false))
    }
}

@Suite struct TimePrimitiveTests {
    @Test func localTimeParsingAndCoding() throws {
        #expect(LocalTime("18:00:00") == LocalTime(hour: 18))
        #expect(LocalTime("09:30") == LocalTime(hour: 9, minute: 30))
        #expect(LocalTime("25:00") == nil)
        #expect(LocalTime(minutesFromMidnight: 1445) == LocalTime(hour: 0, minute: 5))
        let data = try JSONEncoder().encode([LocalTime(hour: 7, minute: 5)])
        #expect(String(decoding: data, as: UTF8.self) == "[\"07:05:00\"]")
        #expect(try JSONDecoder().decode([LocalTime].self, from: data) == [LocalTime(hour: 7, minute: 5)])
    }

    @Test func localDayUsesTheGivenZone() {
        // 03:30 UTC on Nov 11 is still Nov 10 in New York.
        let instant = local(2026, 11, 11, 3, 30, in: TimeZone(identifier: "UTC")!)
        let utc = LocalDay(instant, calendar: .gregorian(in: TimeZone(identifier: "UTC")!))
        let ny = LocalDay(instant, calendar: .gregorian(in: newYork))
        #expect(ny < utc)
        #expect(LocalDay("2026-11-14")?.description == "2026-11-14")
        #expect(LocalDay("nope") == nil)
    }

    @Test func isoWeekday() {
        let calendar = Calendar.gregorian(in: newYork)
        #expect(calendar.isoWeekday(of: local(2026, 11, 9, 12)) == 1) // Monday
        #expect(calendar.isoWeekday(of: local(2026, 11, 15, 12)) == 7) // Sunday
    }

    @Test func scheduleCodingMatchesTheDatabaseShape() throws {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","name":"","weekdays":[1,2,3],"startLocal":"18:00:00","endLocal":"09:00:00","enabled":true}"#
        let s = try JSONDecoder().decode(ProtectedSchedule.self, from: Data(json.utf8))
        #expect(s.weekdays == [1, 2, 3] && s.startLocal.hour == 18)
        let proposal = ScheduleProposal.schedule(s)
        let round = try JSONDecoder().decode(ScheduleProposal.self, from: JSONEncoder().encode(proposal))
        #expect(round == proposal)
        let fewer = try JSONDecoder().decode(ScheduleProposal.self, from: JSONEncoder().encode(ScheduleProposal.fewerPausedApps))
        #expect(fewer == .fewerPausedApps)
    }

    @Test func durations() {
        let en = Locale(identifier: "en_US")
        #expect(DurationText.short(2 * 3600 + 14 * 60, locale: en) == "2h 14m")
        #expect(DurationText.short(45 * 60, locale: en) == "45m")
        #expect(DurationText.short(30, locale: en) == "1m")
        #expect(DurationText.spoken(3600 + 20 * 60, locale: en) == "1 hour, 20 minutes")
    }
}
