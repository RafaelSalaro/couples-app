import Foundation

/// Rules for unlocks (feature spec §6, decisions P11, P12, P14).
public enum UnlockRules {
    public static let freeLengths = [15, 30, 60]
    public static let defaultLength = 30
    public static let step = 15
    public static let minimumLength = 15
    /// Upper bound of the premium length picker (decisions log E9).
    public static let maximumLength = 240
    public static let requestValidity: TimeInterval = 5 * 60
    public static let emailFallbackDelay: TimeInterval = 2 * 60
    public static let maxRequestsPerHour = 3
    public static let accountabilityCodeLength = 6
    public static let maxCodeAttempts = 5

    public static func allowedLengths(isPremium: Bool) -> [Int] {
        isPremium ? Array(stride(from: minimumLength, through: maximumLength, by: step)) : freeLengths
    }

    public static func isValidLength(_ minutes: Int, isPremium: Bool) -> Bool {
        allowedLengths(isPremium: isPremium).contains(minutes)
    }

    /// Whole minutes between two instants, rounded up, at least 1 (how use is counted, P14, P26).
    public static func minutesUsed(from start: Date, to end: Date) -> Int {
        max(1, Int((end.timeIntervalSince(start) / 60).rounded(.up)))
    }

    /// Unused whole minutes of an unlock ending early at `now` (refunded for minutes unlocks, P26).
    public static func unusedWholeMinutes(endsAt: Date, now: Date) -> Int {
        max(0, Int((endsAt.timeIntervalSince(now) / 60).rounded(.down)))
    }
}

/// The weekly emergency allowance (feature spec §6.4, decision P14).
public enum EmergencyRules {
    public static let allowanceChoices = [15, 30, 45, 60]
    public static let defaultAllowance = 15
    public static let window: TimeInterval = 7 * 24 * 3600

    /// The current window: it opens at the first emergency use and lasts 7 days; the next use
    /// after it closes opens a new one. Matches `emergency_window` on the server.
    public static func status(allowance: Int, sessions: [Unlock], now: Date) -> EmergencyAllowance {
        let emergencies = sessions.filter { $0.method == .emergency && $0.startedAt <= now }.sorted { $0.startedAt < $1.startedAt }
        var anchor: Date?
        for session in emergencies where anchor.map({ session.startedAt >= $0.addingTimeInterval(window) }) ?? true {
            anchor = session.startedAt
        }
        guard let start = anchor, now < start.addingTimeInterval(window) else {
            return EmergencyAllowance(allowance: allowance, used: 0, renewsAt: nil)
        }
        let used = emergencies.filter { $0.startedAt >= start }.reduce(0) { $0 + $1.minutesCounted }
        return EmergencyAllowance(allowance: allowance, used: used, renewsAt: start.addingTimeInterval(window))
    }
}

/// What the unlock sheet shows about the emergency allowance this week.
public struct EmergencyAllowance: Codable, Hashable, Sendable {
    public var allowance: Int
    public var used: Int
    /// When the full allowance comes back; nil while no window is open.
    public var renewsAt: Date?

    public init(allowance: Int, used: Int, renewsAt: Date?) {
        self.allowance = allowance
        self.used = used
        self.renewsAt = renewsAt
    }

    public var remaining: Int { max(0, allowance - used) }
    public var isUsedUp: Bool { remaining == 0 }
    public static let fresh = EmergencyAllowance(allowance: EmergencyRules.defaultAllowance, used: 0, renewsAt: nil)
}

/// The window during which paused apps are open.
public struct ActiveUnlock: Codable, Hashable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endsAt: Date

    public init(id: UUID, startedAt: Date, endsAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.endsAt = endsAt
    }

    public func isActive(at date: Date) -> Bool { startedAt <= date && date < endsAt }

    /// Starting an unlock while one is running extends the current window (§6).
    public static func starting(id: UUID, minutes: Int, now: Date, current: ActiveUnlock?) -> ActiveUnlock {
        if let current, current.isActive(at: now) {
            return ActiveUnlock(id: id, startedAt: current.startedAt, endsAt: current.endsAt.addingTimeInterval(Double(minutes) * 60))
        }
        return ActiveUnlock(id: id, startedAt: now, endsAt: now.addingTimeInterval(Double(minutes) * 60))
    }
}

/// The "ask your partner" flow as a pure state machine (feature spec §6.2).
public enum UnlockRequestFlow: Equatable, Sendable {
    case idle
    /// Waiting for the partner; the request is valid until `expiresAt`.
    case waiting(UnlockRequest)
    /// "Go for it" (or a redeemed code): the unlock can start.
    case approved(Unlock)
    /// "Let's wait".
    case declined(UnlockRequest)
    /// Nobody answered in 5 minutes.
    case expired(UnlockRequest)
    case cancelled

    public enum Event: Sendable {
        case created(UnlockRequest)
        /// The server reported a new status for the request.
        case updated(UnlockRequest, unlock: Unlock?)
        /// A typed accountability code was accepted.
        case codeRedeemed(Unlock)
        case tick(Date)
        case cancel
        case reset
    }

    public var isTerminal: Bool {
        switch self {
        case .approved, .declined, .expired, .cancelled: true
        case .idle, .waiting: false
        }
    }

    public var request: UnlockRequest? {
        switch self {
        case .waiting(let r), .declined(let r), .expired(let r): r
        default: nil
        }
    }

    /// Whether the email fallback (and so the accountability code) should have gone out by now.
    public func codeEntryAvailable(now: Date) -> Bool {
        guard case .waiting(let request) = self else { return false }
        return request.emailSentAt != nil || now.timeIntervalSince(request.createdAt) >= UnlockRules.emailFallbackDelay
    }

    public func reduce(_ event: Event) -> UnlockRequestFlow {
        switch (self, event) {
        case (_, .reset):
            return .idle
        case (.idle, .created(let request)):
            return request.status == .pending ? .waiting(request) : self
        case (.waiting(let current), .updated(let request, let unlock)) where request.id == current.id:
            switch request.status {
            case .pending: return .waiting(request)
            case .approved, .redeemed:
                // An approval that arrives without an unlock is not usable; keep waiting for the unlock.
                if let unlock { return .approved(unlock) }
                return .waiting(current)
            case .declined: return .declined(request)
            case .expired: return .expired(request)
            case .cancelled: return .cancelled
            }
        case (.waiting, .codeRedeemed(let unlock)):
            return .approved(unlock)
        case (.waiting(let request), .tick(let now)):
            return now >= request.expiresAt ? .expired(request) : self
        case (.waiting, .cancel):
            return .cancelled
        default:
            // Terminal states ignore everything but reset: an approval after expiry never unlocks.
            return self
        }
    }
}
