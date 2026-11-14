import Backend
import Core
import FeatureSupport
import Foundation
import Observation

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// Challenges: the library by category, marking done, confirming for each other, custom
/// challenges and agreeing their value (feature spec §8).
@MainActor @Observable
public final class ChallengesModel {
    public struct Section: Identifiable, Equatable {
        public var category: ChallengeCategory
        public var challenges: [Challenge]
        public var id: ChallengeCategory { category }
    }

    /// A completion together with the challenge it belongs to.
    public struct Pending: Identifiable, Equatable {
        public var completion: ChallengeCompletion
        public var challenge: Challenge
        public var id: UUID { completion.id }
    }

    public let app: AppModel
    public var message: String?

    public init(app: AppModel) { self.app = app }

    public func load() async { await app.refreshChallenges() }

    // MARK: Library

    public var sections: [Section] {
        let active = app.visibleChallenges.filter { $0.status == .active }
        return ChallengeCategory.allCases.compactMap { category in
            let items = active.filter { $0.category == category }
            return items.isEmpty ? nil : Section(category: category, challenges: items)
        }
    }

    /// How many library challenges premium would add (shown as one quiet line, never a wall).
    public var lockedCount: Int {
        app.isPremium ? 0 : app.challenges.filter { $0.tier == .premium && !$0.isCustom && $0.status == .active }.count
    }

    public static func title(_ category: ChallengeCategory) -> String {
        switch category {
        case .together: L("Together")
        case .kindness: L("Solo kindness")
        case .offlineFun: L("Offline fun")
        case .movement: L("Movement")
        }
    }

    public static func symbol(_ category: ChallengeCategory) -> String {
        switch category {
        case .together: "person.2"
        case .kindness: "heart"
        case .offlineFun: "puzzlepiece"
        case .movement: "figure.walk"
        }
    }

    /// "20 min each" for shared challenges, "10 min" otherwise.
    public func earnLine(_ challenge: Challenge) -> String {
        challenge.isShared ? L("\(MinutesText.short(challenge.minutes)) each") : MinutesText.short(challenge.minutes)
    }

    public func challenge(_ id: UUID) -> Challenge? { app.challenges.first { $0.id == id } }

    // MARK: Done and confirm

    private func pending(_ filter: (ChallengeCompletion) -> Bool) -> [Pending] {
        app.completions.filter { $0.status == .awaitingConfirmation && filter($0) }.compactMap { completion in
            challenge(completion.challengeID).map { Pending(completion: completion, challenge: $0) }
        }
    }

    /// Things the partner did, waiting for this person's one-tap confirmation.
    public var toConfirm: [Pending] { pending { $0.completedBy != app.myID } }
    /// Things this person did, waiting for the partner.
    public var waitingForPartner: [Pending] { pending { $0.completedBy == app.myID } }

    public func isWaiting(_ challenge: Challenge) -> Bool {
        waitingForPartner.contains { $0.challenge.id == challenge.id }
    }

    /// Before the partner joins, challenges are a preview (feature spec §2).
    public var canComplete: Bool { app.isPaired }

    public func markDone(_ challenge: Challenge, note: String) async -> Bool {
        do {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await app.deps.backend.completeChallenge(id: challenge.id, note: trimmed.isEmpty ? nil : trimmed)
            await app.refreshChallenges()
            message = nil
            return true
        } catch {
            message = Friendly.message(for: error)
            return false
        }
    }

    public func confirm(_ pending: Pending) async {
        do {
            try await app.deps.backend.confirmCompletion(id: pending.completion.id)
            await app.refreshChallenges()
            await app.refreshMinutes()
            message = nil
        } catch {
            message = Friendly.message(for: error)
            await app.refreshChallenges()
        }
    }

    public func confirmLine(_ pending: Pending) -> String {
        let name = app.partnerName ?? L("Your partner")
        return L("\(name) did “\(pending.challenge.title)”")
    }

    // MARK: Custom challenges (premium)

    /// Custom challenges whose minute value this person is asked to agree to.
    public var valuesToAnswer: [Challenge] {
        app.challenges.filter { $0.isCustom && $0.status == .pendingValueApproval && $0.valueProposedBy != app.myID }
    }

    /// Custom challenges waiting for the partner to agree the value.
    public var valuesWaiting: [Challenge] {
        app.challenges.filter { $0.isCustom && $0.status == .pendingValueApproval && $0.valueProposedBy == app.myID }
    }

    /// "Ana added 'Fix the bike together' for 30 minutes — sounds right?"
    public func valueQuestion(_ challenge: Challenge) -> String {
        let name = app.partnerName ?? L("Your partner")
        if challenge.createdBy == app.myID {
            return L("\(name) suggests \(MinutesText.short(challenge.minutes)) for “\(challenge.title)” — sounds right?")
        }
        return L("\(name) added “\(challenge.title)” for \(MinutesText.short(challenge.minutes)) — sounds right?")
    }

    public var canCreateCustom: Bool { app.isPremium && app.isPaired }

    public func isValidCustom(title: String, minutes: Int) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...80).contains(trimmed.count) && MinutesRules.customChallengeRange.contains(minutes)
    }

    public func createCustom(title: String, description: String, minutes: Int, category: ChallengeCategory, isShared: Bool) async -> Bool {
        do {
            _ = try await app.deps.backend.createCustomChallenge(title: title, description: description, minutes: minutes, category: category, isShared: isShared)
            await app.refreshChallenges()
            message = nil
            return true
        } catch {
            message = Friendly.message(for: error)
            return false
        }
    }

    public func answerValue(_ challenge: Challenge, approve: Bool, counterMinutes: Int? = nil) async {
        do {
            _ = try await app.deps.backend.respondChallengeValue(challengeID: challenge.id, approve: approve, counterMinutes: counterMinutes)
            await app.refreshChallenges()
            message = nil
        } catch {
            message = Friendly.message(for: error)
        }
    }
}
