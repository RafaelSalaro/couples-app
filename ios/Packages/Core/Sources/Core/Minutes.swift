import Foundation

/// Constants of the minutes economy (feature spec §7, §8).
public enum MinutesRules {
    public static let lifetime: TimeInterval = 7 * 24 * 3600
    public static let defaultDailyMax = 60
    public static let dailyMaxRange = 15...240
    public static let dailyMaxStep = 15
    public static let defaultStartingMinutes = 30
    public static let startingMinutesRange = 0...60
    public static let standardResetMinutes = 30
    public static let customChallengeRange = 5...60
    public static let kudosRange = 5...30
    public static let kudosStep = 5
    public static let kudosDailyCap = 60
    public static let resetProposalValidity: TimeInterval = 24 * 3600
}

public enum MinutesError: Error, Equatable, Sendable {
    case insufficient
    case overDailyMax
    case inDebt
}

/// A client-side mirror of the server's ledger rules (doc 05 §1), used by the in-memory
/// backend that the Simulator and UI tests run on. The server remains the source of truth.
public struct MinutesLedger: Sendable, Equatable {
    public let userID: UUID
    public private(set) var lots: [MinuteLot] = []
    public private(set) var debt = 0
    public private(set) var entries: [LedgerEntry] = []

    public init(userID: UUID) { self.userID = userID }

    public var openLots: [MinuteLot] {
        lots.filter { $0.closedAt == nil && $0.remaining > 0 }.sorted { $0.expiresAt < $1.expiresAt }
    }

    public var balance: Int { openLots.reduce(0) { $0 + $1.remaining } - debt }

    /// Minutes spent on unlocks during the local day, net of refunds from unlocks ended early.
    public func spentToday(now: Date, calendar: Calendar) -> Int {
        let today = LocalDay(now, calendar: calendar)
        return -entries.filter { ($0.type == .spendUnlock || $0.type == .unlockRefund) && $0.localDay == today }.reduce(0) { $0 + $1.minutes }
    }

    public func summary(now: Date, calendar: Calendar, dailyMax: Int) -> MinutesSummary {
        MinutesSummary(userID: userID, lots: openLots, debt: debt, spentToday: spentToday(now: now, calendar: calendar), dailyMax: dailyMax)
    }

    private mutating func log(_ type: LedgerType, _ minutes: Int, lot: UUID? = nil, source: UUID? = nil, now: Date, calendar: Calendar) {
        guard minutes != 0 else { return }
        entries.append(LedgerEntry(
            userID: userID, type: type, minutes: minutes, lotID: lot, sourceID: source,
            localDay: LocalDay(now, calendar: calendar), createdAt: now
        ))
    }

    /// Credits minutes: repays debt first; the remainder becomes a lot expiring in 7 days.
    public mutating func grant(_ minutes: Int, type: LedgerType, source: UUID? = nil, now: Date, calendar: Calendar) {
        guard minutes > 0 else { return }
        expire(now: now, calendar: calendar)
        var remainder = minutes
        if debt > 0 {
            let repaid = min(debt, remainder)
            debt -= repaid
            remainder -= repaid
            log(.debtRepay, repaid, source: source, now: now, calendar: calendar)
        }
        guard remainder > 0 else { return }
        let lot = MinuteLot(userID: userID, granted: remainder, remaining: remainder, expiresAt: now.addingTimeInterval(MinutesRules.lifetime), createdAt: now)
        lots.append(lot)
        log(type, remainder, lot: lot.id, source: source, now: now, calendar: calendar)
    }

    /// Spends minutes on an unlock, soonest-expiring lot first.
    public mutating func spend(_ minutes: Int, dailyMax: Int, unlockID: UUID? = nil, now: Date, calendar: Calendar) throws(MinutesError) {
        expire(now: now, calendar: calendar)
        guard debt == 0 else { throw .inDebt }
        guard balance >= minutes else { throw .insufficient }
        guard spentToday(now: now, calendar: calendar) + minutes <= dailyMax else { throw .overDailyMax }
        var left = minutes
        for lot in openLots where left > 0 {
            guard let index = lots.firstIndex(where: { $0.id == lot.id }) else { continue }
            let take = min(lots[index].remaining, left)
            lots[index].remaining -= take
            if lots[index].remaining == 0 { lots[index].closedAt = now }
            left -= take
            log(.spendUnlock, -take, lot: lot.id, source: unlockID, now: now, calendar: calendar)
        }
    }

    /// Emergency unlock: takes the minutes used from the balance, soonest-expiring first; only a
    /// shortfall becomes debt, so the balance can go negative (P14). Matches `borrow_minutes`.
    public mutating func borrow(_ minutes: Int, unlockID: UUID? = nil, now: Date, calendar: Calendar) {
        expire(now: now, calendar: calendar)
        var left = minutes
        for lot in openLots where left > 0 {
            guard let index = lots.firstIndex(where: { $0.id == lot.id }) else { continue }
            let take = min(lots[index].remaining, left)
            lots[index].remaining -= take
            if lots[index].remaining == 0 { lots[index].closedAt = now }
            left -= take
            log(.emergencyBorrow, -take, lot: lot.id, source: unlockID, now: now, calendar: calendar)
        }
        guard left > 0 else { return }
        debt += left
        log(.emergencyBorrow, -left, source: unlockID, now: now, calendar: calendar)
    }

    /// Gives back up to `minutes` an unlock spent, to the lots they came from (keeping their
    /// expiry), latest-expiring first; expired lots are skipped. Returns the minutes refunded (P26).
    @discardableResult
    public mutating func refund(_ minutes: Int, unlockID: UUID, now: Date, calendar: Calendar) -> Int {
        expire(now: now, calendar: calendar)
        var spentByLot: [UUID: (minutes: Int, day: LocalDay)] = [:]
        for entry in entries where entry.type == .spendUnlock && entry.sourceID == unlockID {
            guard let lot = entry.lotID else { continue }
            spentByLot[lot] = ((spentByLot[lot]?.minutes ?? 0) - entry.minutes, entry.localDay)
        }
        var left = minutes
        let order = lots.filter { spentByLot[$0.id] != nil && $0.expiresAt > now }.sorted { $0.expiresAt > $1.expiresAt }
        for lot in order where left > 0 {
            guard let index = lots.firstIndex(where: { $0.id == lot.id }), let spent = spentByLot[lot.id] else { continue }
            let back = min(spent.minutes, left)
            lots[index].remaining += back
            lots[index].closedAt = nil
            left -= back
            entries.append(LedgerEntry(userID: userID, type: .unlockRefund, minutes: back, lotID: lot.id, sourceID: unlockID,
                                       localDay: spent.day, createdAt: now))
        }
        return minutes - left
    }

    /// Closes lots past their expiry and writes `expire` entries.
    public mutating func expire(now: Date, calendar: Calendar) {
        for index in lots.indices where lots[index].closedAt == nil && lots[index].expiresAt <= now {
            let lost = lots[index].remaining
            lots[index].remaining = 0
            lots[index].closedAt = now
            log(.expire, -lost, lot: lots[index].id, now: now, calendar: calendar)
        }
    }

    /// Mutual reset or unpair: expires everything (lots and debt), then grants `standard` minutes if any.
    public mutating func reset(to standard: Int, source: UUID? = nil, now: Date, calendar: Calendar) {
        for index in lots.indices where lots[index].closedAt == nil {
            let lost = lots[index].remaining
            lots[index].remaining = 0
            lots[index].closedAt = now
            log(.expire, -lost, lot: lots[index].id, source: source, now: now, calendar: calendar)
        }
        debt = 0
        guard standard > 0 else { return }
        let lot = MinuteLot(userID: userID, granted: standard, remaining: standard, expiresAt: now.addingTimeInterval(MinutesRules.lifetime), createdAt: now)
        lots.append(lot)
        log(.reset, standard, lot: lot.id, source: source, now: now, calendar: calendar)
    }
}

/// One day of the Minutes screen's expiration timeline.
public struct ExpiryBucket: Hashable, Sendable, Identifiable {
    public var day: LocalDay
    public var date: Date
    public var minutes: Int
    public var id: LocalDay { day }
}

public enum ExpiryTimeline {
    /// Minutes expiring on each of the coming days. Lots live 7 days, so they expire today … 7 days out;
    /// today is left out when nothing expires today, giving a 7-day chart.
    public static func buckets(lots: [MinuteLot], now: Date, calendar: Calendar) -> [ExpiryBucket] {
        let today = calendar.startOfDay(for: now)
        var buckets: [ExpiryBucket] = (0...7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return ExpiryBucket(day: LocalDay(date, calendar: calendar), date: date, minutes: 0)
        }
        for lot in lots where lot.remaining > 0 && lot.closedAt == nil && lot.expiresAt > now {
            let day = LocalDay(lot.expiresAt, calendar: calendar)
            if let index = buckets.firstIndex(where: { $0.day == day }) {
                buckets[index].minutes += lot.remaining
            }
        }
        if let first = buckets.first, first.minutes == 0 { buckets.removeFirst() } else { buckets.removeLast() }
        return buckets
    }

    /// Minutes that expire during tomorrow's local day (for the evening reminder).
    public static func expiringTomorrow(lots: [MinuteLot], now: Date, calendar: Calendar) -> Int {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return 0 }
        let day = LocalDay(tomorrow, calendar: calendar)
        return lots.filter { $0.remaining > 0 && $0.closedAt == nil && LocalDay($0.expiresAt, calendar: calendar) == day }
            .reduce(0) { $0 + $1.remaining }
    }
}
