import Foundation

/// Evaluates protected-time schedules in the user's local time zone.
///
/// A schedule's weekdays are the days on which it *starts*. A schedule whose end is at or
/// before its start runs into the next day (the default 18:00–09:00 does).
public struct ScheduleEvaluator: Sendable {
    public let calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        calendar = .gregorian(in: timeZone)
    }

    /// The occurrence of `schedule` that starts on the local day containing `day`, if it runs that day.
    public func occurrence(of schedule: ProtectedSchedule, startingOnDayOf day: Date) -> DateInterval? {
        guard schedule.enabled, schedule.weekdays.contains(calendar.isoWeekday(of: day)) else { return nil }
        let dayStart = calendar.startOfDay(for: day)
        var startParts = calendar.dateComponents([.year, .month, .day], from: dayStart)
        startParts.hour = schedule.startLocal.hour
        startParts.minute = schedule.startLocal.minute
        guard let start = calendar.date(from: startParts) else { return nil }
        let endDay = schedule.crossesMidnight
            ? (calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart)
            : dayStart
        var endParts = calendar.dateComponents([.year, .month, .day], from: endDay)
        endParts.hour = schedule.endLocal.hour
        endParts.minute = schedule.endLocal.minute
        guard let end = calendar.date(from: endParts), end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Occurrences starting on the days from `dayOffsets` relative to `date`.
    private func occurrences(of schedules: [ProtectedSchedule], around date: Date, dayOffsets: ClosedRange<Int>) -> [DateInterval] {
        let today = calendar.startOfDay(for: date)
        var result: [DateInterval] = []
        for offset in dayOffsets {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            // Noon avoids any ambiguity on daylight-saving transition days.
            let probe = calendar.date(byAdding: .hour, value: 12, to: day) ?? day
            for schedule in schedules {
                if let interval = occurrence(of: schedule, startingOnDayOf: probe) { result.append(interval) }
            }
        }
        return result
    }

    /// True when `date` falls inside any enabled schedule. The end instant itself is not protected.
    public func isProtected(at date: Date, schedules: [ProtectedSchedule]) -> Bool {
        occurrences(of: schedules, around: date, dayOffsets: -1...0).contains { $0.start <= date && date < $0.end }
    }

    /// The continuous stretch of protected time around `date` (overlapping or touching schedules are merged).
    public func currentProtection(at date: Date, schedules: [ProtectedSchedule]) -> DateInterval? {
        let all = occurrences(of: schedules, around: date, dayOffsets: -2...8).sorted { $0.start < $1.start }
        guard var merged = all.first(where: { $0.start <= date && date < $0.end }) else { return nil }
        var changed = true
        while changed {
            changed = false
            for interval in all where interval.start <= merged.end && interval.end >= merged.start {
                let union = DateInterval(start: min(merged.start, interval.start), end: max(merged.end, interval.end))
                if union != merged {
                    merged = union
                    changed = true
                }
            }
        }
        return merged
    }

    /// When protected time ends, if it is on now.
    public func protectionEnd(at date: Date, schedules: [ProtectedSchedule]) -> Date? {
        currentProtection(at: date, schedules: schedules)?.end
    }

    /// The next time protected time starts strictly after `date`.
    public func nextStart(after date: Date, schedules: [ProtectedSchedule]) -> Date? {
        occurrences(of: schedules, around: date, dayOffsets: 0...8).map(\.start).filter { $0 > date }.min()
    }
}

/// Classifies a schedule edit as stricter or looser (feature spec §4, decision P10).
public enum ScheduleChange: Sendable, Equatable {
    /// Nothing about protected time changes.
    case same
    /// Only adds protected time: applies immediately.
    case stricter
    /// Removes some protected time: needs partner approval when paired.
    case looser

    static let minutesPerWeek = 7 * 1440

    /// The protected minutes of a week (Monday 00:00 = 0) for a set of schedules.
    public static func coverage(_ schedules: [ProtectedSchedule]) -> [Bool] {
        var week = [Bool](repeating: false, count: minutesPerWeek)
        for schedule in schedules where schedule.enabled {
            for weekday in schedule.weekdays where (1...7).contains(weekday) {
                let start = (weekday - 1) * 1440 + schedule.startLocal.minutesFromMidnight
                for minute in start..<(start + schedule.lengthMinutes) {
                    week[minute % minutesPerWeek] = true
                }
            }
        }
        return week
    }

    /// Any protected minute that would be lost makes the change looser, even if other minutes are added.
    public static func classify(from old: [ProtectedSchedule], to new: [ProtectedSchedule]) -> ScheduleChange {
        let before = coverage(old), after = coverage(new)
        var added = false
        for index in 0..<minutesPerWeek {
            if before[index] && !after[index] { return .looser }
            if !before[index] && after[index] { added = true }
        }
        return added ? .stricter : .same
    }

    /// Whether the change can be applied right away.
    public static func appliesImmediately(_ change: ScheduleChange, isPaired: Bool) -> Bool {
        !isPaired || change != .looser
    }
}
