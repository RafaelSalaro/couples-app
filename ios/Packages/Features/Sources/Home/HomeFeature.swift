import Core
import DesignSystem
import FeatureSupport
import Foundation
import SwiftUI

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// What the home ring shows: time left in protected time, an unlock countdown, or when protected time starts.
public struct RingStatus: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case protected, unlocked, open, off }
    public var mode: Mode
    public var progress: Double
    /// Big text in the ring ("2h 14m").
    public var value: String
    /// Small text under it ("of protected time left").
    public var caption: String
    /// Full sentence for VoiceOver ("1 hour, 20 minutes of protected time left").
    public var spoken: String

    public static func make(state: SharedState, needsAccess: Bool, now: Date, timeZone: TimeZone, locale: Locale = .current) -> RingStatus {
        if needsAccess {
            return RingStatus(mode: .off, progress: 0, value: L("Off"), caption: L("Protected time is off"), spoken: L("Protected time is off"))
        }
        switch state.phase(at: now, timeZone: timeZone) {
        case .protected(let until):
            let total = ScheduleEvaluator(timeZone: timeZone).currentProtection(at: now, schedules: state.schedules)?.duration ?? 1
            let left = until.timeIntervalSince(now)
            return RingStatus(
                mode: .protected, progress: 1 - left / max(total, 1), value: DurationText.short(left, locale: locale),
                caption: L("of protected time left"),
                spoken: L("\(DurationText.spoken(left, locale: locale)) of protected time left")
            )
        case .unlocked(let until):
            let left = until.timeIntervalSince(now)
            let total = state.activeUnlock.map { $0.endsAt.timeIntervalSince($0.startedAt) } ?? left
            return RingStatus(
                mode: .unlocked, progress: left / max(total, 1), value: DurationText.short(left, locale: locale),
                caption: L("unlocked"),
                spoken: L("Unlocked for \(DurationText.spoken(left, locale: locale)) more")
            )
        case .open(let next):
            guard let next else {
                return RingStatus(mode: .open, progress: 0, value: L("Open"), caption: L("No protected time set"), spoken: L("No protected time set"))
            }
            let clock = ScheduleText.clock(next, timeZone: timeZone, locale: locale)
            return RingStatus(
                mode: .open, progress: 0, value: clock, caption: L("protected time starts"),
                spoken: L("Protected time starts at \(clock)")
            )
        }
    }
}
