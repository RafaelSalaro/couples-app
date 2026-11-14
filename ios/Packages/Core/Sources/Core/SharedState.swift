import Foundation

/// The small state the app shares with its extensions through the App Group container,
/// so the Monitor, Shield and Widget extensions work without the network.
/// It never contains which apps are paused; the selection tokens are stored separately as opaque data.
public struct SharedState: Codable, Equatable, Sendable {
    public var schedules: [ProtectedSchedule] = []
    public var activeUnlock: ActiveUnlock?
    /// False when the user has no Screen Time authorization or no selection yet.
    public var protectionConfigured = false
    public var myName: String?
    public var partnerName: String?
    public var myBalance: Int?
    public var partnerBalance: Int?
    public var streak: Int?
    /// Set by the Shield Action extension when "Ask" is tapped; the app opens the unlock sheet.
    public var unlockPromptRequestedAt: Date?
    /// Mock only: whether the simulated shield is up.
    public var mockShieldApplied = false

    public init() {}

    public func isUnlocked(at date: Date) -> Bool { activeUnlock?.isActive(at: date) ?? false }

    public enum Phase: Equatable, Sendable {
        /// Outside protected time; `next` is when it starts again.
        case open(next: Date?)
        case protected(until: Date)
        case unlocked(until: Date)
    }

    /// What the home ring, widgets and shield show right now.
    public func phase(at date: Date, timeZone: TimeZone = .current) -> Phase {
        let evaluator = ScheduleEvaluator(timeZone: timeZone)
        guard let protection = evaluator.currentProtection(at: date, schedules: schedules) else {
            return .open(next: evaluator.nextStart(after: date, schedules: schedules))
        }
        if let unlock = activeUnlock, unlock.isActive(at: date) {
            return .unlocked(until: min(unlock.endsAt, protection.end))
        }
        return .protected(until: protection.end)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schedules = try c.decodeIfPresent([ProtectedSchedule].self, forKey: .schedules) ?? []
        activeUnlock = try c.decodeIfPresent(ActiveUnlock.self, forKey: .activeUnlock)
        protectionConfigured = try c.decodeIfPresent(Bool.self, forKey: .protectionConfigured) ?? false
        myName = try c.decodeIfPresent(String.self, forKey: .myName)
        partnerName = try c.decodeIfPresent(String.self, forKey: .partnerName)
        myBalance = try c.decodeIfPresent(Int.self, forKey: .myBalance)
        partnerBalance = try c.decodeIfPresent(Int.self, forKey: .partnerBalance)
        streak = try c.decodeIfPresent(Int.self, forKey: .streak)
        unlockPromptRequestedAt = try c.decodeIfPresent(Date.self, forKey: .unlockPromptRequestedAt)
        mockShieldApplied = try c.decodeIfPresent(Bool.self, forKey: .mockShieldApplied) ?? false
    }
}

/// Reads and writes `SharedState` and the opaque paused-apps selection.
public protocol SharedStateStore: Sendable {
    func load() -> SharedState
    func save(_ state: SharedState)
    func loadSelectionData() -> Data?
    func saveSelectionData(_ data: Data?)
}

public extension SharedStateStore {
    @discardableResult
    func update(_ mutate: (inout SharedState) -> Void) -> SharedState {
        var state = load()
        mutate(&state)
        save(state)
        return state
    }
}

/// App Group backed store (UserDefaults suite). Falls back to standard defaults when the
/// App Group is not available (unit tests, misconfigured builds).
public final class AppGroupStateStore: SharedStateStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private static let stateKey = "shared_state_v1"
    private static let selectionKey = "paused_apps_selection_v1"

    public init(suiteName: String? = AppGroupStateStore.appGroupID) {
        defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The App Group identifier, set once in `Config/Shared.xcconfig` and carried in every target's Info.plist.
    public static var appGroupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
    }

    public func load() -> SharedState {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.stateKey),
              let state = try? JSONDecoder().decode(SharedState.self, from: data) else { return SharedState() }
        return state
    }

    public func save(_ state: SharedState) {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.stateKey) }
    }

    public func loadSelectionData() -> Data? { defaults.data(forKey: Self.selectionKey) }

    public func saveSelectionData(_ data: Data?) {
        if let data { defaults.set(data, forKey: Self.selectionKey) } else { defaults.removeObject(forKey: Self.selectionKey) }
    }

    /// Clears everything (sign-out, UI-test reset).
    public func reset() {
        defaults.removeObject(forKey: Self.stateKey)
        defaults.removeObject(forKey: Self.selectionKey)
    }
}

public final class InMemoryStateStore: SharedStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state = SharedState()
    private var selection: Data?

    public init(_ state: SharedState = SharedState()) { self.state = state }

    public func load() -> SharedState { lock.withLock { state } }
    public func save(_ state: SharedState) { lock.withLock { self.state = state } }
    public func loadSelectionData() -> Data? { lock.withLock { selection } }
    public func saveSelectionData(_ data: Data?) { lock.withLock { selection = data } }
}

/// Deep links and universal links (06 §9).
public enum DeepLink: Equatable, Sendable {
    case unlock
    case request(UUID)
    case challenge(UUID)
    /// `https://<domain>/i/<token>` or `couplesapp://invite/<token-or-code>`.
    case invite(String)
    /// Magic-link sign-in callback, handed to the auth layer untouched.
    case authCallback(URL)

    public static func parse(_ url: URL, scheme: String, domain: String) -> DeepLink? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme?.lowercased() == scheme.lowercased() {
            switch url.host?.lowercased() {
            case "unlock": return .unlock
            case "request": return parts.first.flatMap(UUID.init(uuidString:)).map(DeepLink.request)
            case "challenge": return parts.first.flatMap(UUID.init(uuidString:)).map(DeepLink.challenge)
            case "invite": return parts.first.map(DeepLink.invite)
            case "auth", "login-callback": return .authCallback(url)
            default: return nil
            }
        }
        if url.scheme == "https", url.host?.lowercased() == domain.lowercased(), parts.count == 2, parts[0] == "i" {
            return .invite(parts[1])
        }
        return nil
    }
}

/// Errors returned by the backend, with the codes of doc 05 §3.
public struct BackendError: Error, Equatable, Sendable {
    public enum Code: String, Sendable, CaseIterable {
        case alreadyPaired = "already_paired"
        case invalid, expired
        case notPaired = "not_paired"
        case rateLimited = "rate_limited"
        case partnerMissing = "partner_missing"
        case notPartner = "not_partner"
        case tooManyAttempts = "too_many_attempts"
        case insufficient
        case overDailyMax = "over_daily_max"
        case inDebt = "in_debt"
        case usedThisWeek = "used_this_week"
        case duplicateCounter = "duplicate_counter"
        case premiumRequired = "premium_required"
        case dailyCap = "daily_cap"
        case notSignedIn = "not_signed_in"
        case offline
        case unknown
    }

    public var code: Code
    public var message: String

    public init(_ code: Code, message: String = "") {
        self.code = code
        self.message = message
    }

    public init(rawCode: String, message: String = "") {
        self.init(Code(rawValue: rawCode) ?? .unknown, message: message.isEmpty ? rawCode : message)
    }
}

/// Short spoken and visual durations ("2h 14m", "45m"), localized by the system.
public enum DurationText {
    public static func short(_ interval: TimeInterval, locale: Locale = .current) -> String {
        let minutes = max(0, Int((interval / 60).rounded(.up)))
        let duration = Duration.seconds(minutes * 60)
        let units: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        return duration.formatted(.units(allowed: units, width: .narrow).locale(locale))
    }

    /// Full words for VoiceOver ("2 hours, 14 minutes").
    public static func spoken(_ interval: TimeInterval, locale: Locale = .current) -> String {
        let minutes = max(0, Int((interval / 60).rounded(.up)))
        let units: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(minutes * 60).formatted(.units(allowed: units, width: .wide).locale(locale))
    }
}
