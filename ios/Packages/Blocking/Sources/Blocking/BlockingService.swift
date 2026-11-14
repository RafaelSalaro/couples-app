import Core
import Foundation

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

public enum BlockingAuthorization: String, Sendable, Codable {
    case notDetermined, approved, denied
}

public enum BlockingError: Error, Equatable, Sendable {
    /// The user declined Screen Time access.
    case authorizationDenied
    /// An operation needed Screen Time access that is not there (never granted, or revoked).
    case notAuthorized
    /// Unlocks are at least 15 minutes (Device Activity minimum, decisions P12, T6).
    case unlockTooShort
    case system(String)
}

public enum BlockingKind: String, Sendable { case screenTime, mock }

/// The apps, categories and websites a user chose to pause. Opaque on purpose:
/// with Screen Time it wraps `FamilyActivitySelection` tokens, which never leave the phone.
public struct PausedAppsSelection: Codable, Equatable, Sendable {
    /// Encoded selection (tokens). Stored only in the App Group container.
    public var data: Data
    public var applicationCount: Int
    public var categoryCount: Int
    public var webDomainCount: Int

    public init(data: Data, applicationCount: Int, categoryCount: Int, webDomainCount: Int) {
        self.data = data
        self.applicationCount = applicationCount
        self.categoryCount = categoryCount
        self.webDomainCount = webDomainCount
    }

    public var isEmpty: Bool { applicationCount + categoryCount + webDomainCount == 0 }
}

/// The seam that lets the app be built and tested in the Simulator before the Family Controls
/// entitlement and a device are available (06 §3).
public protocol BlockingService: Sendable {
    var kind: BlockingKind { get }
    func requestAuthorization() async throws
    var authorizationStatus: BlockingAuthorization { get }
    func saveSelection(_ selection: PausedAppsSelection) throws
    func currentSelection() -> PausedAppsSelection?
    func applySchedule(_ schedules: [ProtectedSchedule]) throws
    /// Opens paused apps for `minutes` (at least 15). While an unlock is running this extends it.
    func startUnlock(id: UUID, minutes: Int) throws
    func endUnlockEarly(id: UUID) throws
    func isProtectedNow() -> Bool
    /// Whether going from `old` to `new` pauses fewer apps (looser), more (stricter) or the same.
    func selectionChange(from old: PausedAppsSelection?, to new: PausedAppsSelection) -> ScheduleChange
}

public extension BlockingService {
    /// True when Screen Time access was granted and has since been taken away, or was declined.
    var needsAuthorization: Bool { authorizationStatus != .approved }
}

/// Compares two sets of opaque tokens: losing any token is looser; only gaining is stricter.
func tokenSetChange<T: Hashable>(from old: Set<T>, to new: Set<T>) -> ScheduleChange {
    if !old.isSubset(of: new) { return .looser }
    return new.count > old.count ? .stricter : .same
}

/// Text of the pause screen (feature spec §5), shared by the Shield Configuration extension
/// and the simulated shield.
public struct ShieldContent: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var primaryButton: String
    public var secondaryButton: String

    /// Number of inviting lines that rotate under the time remaining.
    static let lineCount = 4

    static func invitingLine(_ index: Int, partner: String?) -> String {
        switch (index % lineCount, partner) {
        case (1, let partner?): L("\(partner) is around — say hi?")
        case (2, _): L("A good moment to look up.")
        case (3, let partner?): L("What would you and \(partner) like to do?")
        default: L("Want to do something together?")
        }
    }

    public static func make(state: SharedState, now: Date, timeZone: TimeZone = .current, lineIndex: Int? = nil) -> ShieldContent {
        let partner = state.partnerName
        var lines: [String] = []
        if case .protected(let until) = state.phase(at: now, timeZone: timeZone) {
            lines.append(L("\(DurationText.short(until.timeIntervalSince(now))) left"))
        }
        // Rotate through the lines over time so the screen does not always say the same thing.
        let index = lineIndex ?? Int(now.timeIntervalSince1970 / 600)
        lines.append(invitingLine(index, partner: partner))
        return ShieldContent(
            title: L("Protected time"),
            subtitle: lines.joined(separator: "\n"),
            primaryButton: partner.map { L("Ask \($0)") } ?? L("Unlock options"),
            secondaryButton: L("Not now")
        )
    }
}

/// The local notification the Shield Action extension posts when "Ask" is tapped
/// (a shield button cannot open the app: decision T3).
public struct ShieldPrompt: Equatable, Sendable {
    public static let identifier = "shield-unlock-prompt"
    public var title: String
    public var body: String
    /// `couplesapp://unlock`
    public var deepLink: URL?

    public static func make(state: SharedState, urlScheme: String) -> ShieldPrompt {
        ShieldPrompt(
            title: L("Protected time"),
            body: state.partnerName.map { L("Tap to ask \($0) or use your minutes") } ?? L("Tap to see your unlock options"),
            deepLink: URL(string: "\(urlScheme)://unlock")
        )
    }
}
