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
    public static let emergencyMinutes = 15
    public static let emergencyCooldown: TimeInterval = 7 * 24 * 3600
    public static let accountabilityCodeLength = 6
    public static let maxCodeAttempts = 5

    public static func allowedLengths(isPremium: Bool) -> [Int] {
        isPremium ? Array(stride(from: minimumLength, through: maximumLength, by: step)) : freeLengths
    }

    public static func isValidLength(_ minutes: Int, isPremium: Bool) -> Bool {
        allowedLengths(isPremium: isPremium).contains(minutes)
    }

    /// When the next emergency unlock becomes available, or nil if it is available now.
    public static func emergencyAvailableAt(lastUsed: Date?, now: Date) -> Date? {
        guard let lastUsed else { return nil }
        let next = lastUsed.addingTimeInterval(emergencyCooldown)
        return next > now ? next : nil
    }
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
