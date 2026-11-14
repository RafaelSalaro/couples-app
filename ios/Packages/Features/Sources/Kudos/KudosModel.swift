import Backend
import Core
import FeatureSupport
import Foundation
import Observation

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// Giving kudos: minutes awarded unprompted, "I noticed you" (feature spec §8, premium).
@MainActor @Observable
public final class KudosModel {
    public let app: AppModel
    public let challengeID: UUID?
    public var minutes = 10
    public var note = ""
    public var message: String?
    public private(set) var givenToday = 0
    public private(set) var sent: Kudos?

    public init(app: AppModel, challengeID: UUID? = nil) {
        self.app = app
        self.challengeID = challengeID
        if let challenge = app.challenges.first(where: { $0.id == challengeID }) {
            minutes = min(max(MinutesRules.kudosRange.lowerBound, challenge.minutes / 5 * 5), MinutesRules.kudosRange.upperBound)
            note = challenge.title
        }
    }

    public var partnerName: String { app.partnerName ?? L("your partner") }
    public var isPremium: Bool { app.isPremium }
    public var amounts: [Int] { Array(stride(from: MinutesRules.kudosRange.lowerBound, through: MinutesRules.kudosRange.upperBound, by: MinutesRules.kudosStep)) }
    /// Minutes of kudos still available today (60 per giver per day).
    public var remainingToday: Int { max(0, MinutesRules.kudosDailyCap - givenToday) }
    public var canGive: Bool { app.isPaired && isPremium && minutes <= remainingToday && note.count <= 140 }

    /// A few ready lines; people can always write their own.
    public var suggestions: [String] {
        [L("You made me laugh today"), L("Thank you for today"), L("I noticed what you did"), L("That meant a lot")]
    }

    public func load() async {
        guard let kudos = try? await app.deps.backend.fetchKudos(limit: 50) else { return }
        let calendar = Calendar.gregorian(in: app.deps.timeZone())
        let now = app.deps.now()
        givenToday = kudos.filter { $0.giverID == app.myID && calendar.isDate($0.createdAt, inSameDayAs: now) }.reduce(0) { $0 + $1.minutes }
        if minutes > remainingToday, let fit = amounts.last(where: { $0 <= remainingToday }) { minutes = fit }
    }

    public var remainingLine: String {
        remainingToday > 0
            ? L("\(MinutesText.short(remainingToday)) of kudos left to give today.")
            : L("You've given all of today's kudos. More tomorrow.")
    }

    public func give() async {
        do {
            sent = try await app.deps.backend.giveKudos(minutes: minutes, message: note.trimmingCharacters(in: .whitespacesAndNewlines), challengeID: challengeID)
            message = nil
            await app.refreshMinutes()
            await app.refreshActivity()
        } catch {
            message = Friendly.message(for: error)
            await load()
        }
    }

    public var sentLine: String? {
        sent.map { L("\(partnerName) just got \(MinutesText.short($0.minutes)) from you.") }
    }
}

/// Wording for kudos that arrived: "Ana says you made her laugh · +10 min" is written by the
/// giver, so the app shows their own words.
public enum KudosText {
    public static func title(from partnerName: String) -> String { L("Kudos from \(partnerName)") }

    public static func body(_ kudos: Kudos, partnerName: String) -> String {
        kudos.message.isEmpty ? L("\(partnerName) noticed you.") : "“\(kudos.message)”"
    }

    public static func amount(_ kudos: Kudos) -> String { "+\(MinutesText.short(kudos.minutes))" }
}
