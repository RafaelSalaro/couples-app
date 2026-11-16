import Backend
import Core
import FeatureSupport
import Foundation
import Observation

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// The Minutes screen: balances, the 7-day expiration timeline, ledger history and mutual reset (feature spec §7).
@MainActor @Observable
public final class MinutesModel {
    public enum Person: Hashable, Sendable { case me, partner }

    public let app: AppModel
    public private(set) var ledger: [LedgerEntry] = []
    public var showing = Person.me
    public var message: String?

    public init(app: AppModel) { self.app = app }

    public func load() async {
        await app.refreshMinutes()
        await app.refreshRequests()
        if let entries = try? await app.deps.backend.fetchLedger(limit: 100) { ledger = entries }
    }

    private var calendar: Calendar { .gregorian(in: app.deps.timeZone()) }

    public func summary(_ person: Person) -> MinutesSummary? { person == .me ? app.myMinutes : app.partnerMinutes }

    /// What expires when, for the coming days (partners see each other's timeline too: rule 11).
    public func buckets(_ person: Person) -> [ExpiryBucket] {
        ExpiryTimeline.buckets(lots: summary(person)?.lots ?? [], now: app.deps.now(), calendar: calendar)
    }

    public func dayName(_ bucket: ExpiryBucket, style: Date.FormatStyle.Symbol.Weekday = .wide) -> String {
        var format = Date.FormatStyle.dateTime.weekday(style)
        format.timeZone = app.deps.timeZone()
        return bucket.date.formatted(format)
    }

    /// "12 min expire Thursday · 20 min Saturday"
    public func timelineSummary(_ person: Person) -> String {
        let parts = buckets(person).filter { $0.minutes > 0 }
        guard let first = parts.first else { return L("Nothing expires in the next 7 days.") }
        let rest = parts.dropFirst().map { L("\(MinutesText.short($0.minutes)) \(dayName($0))") }
        return ([L("\(MinutesText.short(first.minutes)) expire \(dayName(first))")] + rest).joined(separator: " · ")
    }

    /// Height of a bar relative to the tallest one.
    public func fraction(_ bucket: ExpiryBucket, in buckets: [ExpiryBucket]) -> Double {
        let top = buckets.map(\.minutes).max() ?? 0
        return top == 0 ? 0 : Double(bucket.minutes) / Double(top)
    }

    public func balanceLine(_ person: Person) -> String {
        guard let summary = summary(person) else { return "" }
        if summary.debt > 0 {
            return person == .me
                ? L("You borrowed \(MinutesText.short(summary.debt)) for an emergency unlock. New minutes repay it first.")
                : L("\(app.partnerName ?? "") borrowed \(MinutesText.short(summary.debt)) for an emergency unlock.")
        }
        return person == .me
            ? L("\(MinutesText.short(summary.remainingToday)) left to spend today (daily maximum \(MinutesText.short(summary.dailyMax))).")
            : L("Each minute lasts 7 days from when it was earned.")
    }

    // MARK: History

    public func title(_ entry: LedgerEntry) -> String {
        switch entry.type {
        case .startingGrant: L("Starting minutes")
        case .earnChallenge: L("Challenge")
        case .earnKudos: L("Kudos")
        case .spendUnlock: L("Unlock")
        case .emergencyBorrow: L("Emergency unlock")
        case .debtRepay: L("Earned back")
        case .reset: L("Fresh start")
        case .expire: L("Expired")
        case .adminAdjust: L("Adjustment")
        case .unlockRefund: L("Unlock ended early")
        }
    }

    public func amount(_ entry: LedgerEntry) -> String {
        let value = MinutesText.short(abs(entry.minutes))
        return entry.minutes >= 0 ? "+\(value)" : "−\(value)"
    }

    public func date(_ entry: LedgerEntry) -> String {
        var format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        format.timeZone = app.deps.timeZone()
        return entry.createdAt.formatted(format)
    }

    // MARK: Mutual reset

    /// A reset the partner proposed, waiting for this person.
    public var incomingReset: ResetProposal? { app.resetProposals.first { $0.proposerID != app.myID } }
    /// A reset this person proposed, waiting for the partner.
    public var outgoingReset: ResetProposal? { app.resetProposals.first { $0.proposerID == app.myID } }
    public var standardMinutes: Int { app.pair?.pair.standardResetMinutes ?? MinutesRules.standardResetMinutes }
    public var canProposeReset: Bool { app.isPaired && app.resetProposals.isEmpty }

    public func proposeReset() async {
        do {
            _ = try await app.deps.backend.proposeReset(standardMinutes: standardMinutes)
            await app.refreshRequests()
            message = nil
        } catch {
            message = Friendly.message(for: error)
        }
    }

    public func respondReset(_ proposal: ResetProposal, accept: Bool) async {
        do {
            try await app.deps.backend.respondReset(proposalID: proposal.id, accept: accept)
            await load()
        } catch {
            message = Friendly.message(for: error)
            await app.refreshRequests()
        }
    }
}
