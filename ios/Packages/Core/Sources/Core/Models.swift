import Foundation

// MARK: - Time primitives

/// A wall-clock time of day (no date, no time zone), as stored in `schedules.start_local`.
public struct LocalTime: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public init(minutesFromMidnight: Int) {
        let m = ((minutesFromMidnight % 1440) + 1440) % 1440
        self.init(hour: m / 60, minute: m % 60)
    }

    /// Parses "HH:mm" or "HH:mm:ss".
    public init?(_ string: String) {
        let parts = string.split(separator: ":").map { Int($0.prefix(2)) }
        guard parts.count >= 2, let h = parts[0], let m = parts[1], (0...23).contains(h), (0...59).contains(m) else {
            return nil
        }
        self.init(hour: h, minute: m)
    }

    public var minutesFromMidnight: Int { hour * 60 + minute }
    public var description: String { String(format: "%02d:%02d:00", hour, minute) }
    public static func < (a: LocalTime, b: LocalTime) -> Bool { a.minutesFromMidnight < b.minutesFromMidnight }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = LocalTime(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad time \(raw)"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// A calendar day in someone's local time zone ("2026-11-14"), as stored in `date` columns.
public struct LocalDay: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public init?(_ string: String) {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public func startDate(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public static func < (a: LocalDay, b: LocalDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = LocalDay(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad day \(raw)"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public extension Calendar {
    /// Gregorian calendar fixed to a time zone, used for all schedule and local-day math.
    static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    /// ISO weekday of a date: 1 = Monday … 7 = Sunday (as stored in `schedules.weekdays`).
    func isoWeekday(of date: Date) -> Int {
        (component(.weekday, from: date) + 5) % 7 + 1
    }
}

/// Injected clock so time-dependent logic can be tested.
public typealias NowProvider = @Sendable () -> Date

// MARK: - Identity and pairing

public struct UserProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String?
    public var photoPath: String?
    public var timeZone: String
    public var locale: String
    /// Set while Screen Time permission is revoked or protected time is turned off (P23).
    public var protectedTimeOffSince: Date?

    public init(
        id: UUID, displayName: String? = nil, photoPath: String? = nil,
        timeZone: String = TimeZone.current.identifier, locale: String = "en",
        protectedTimeOffSince: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.photoPath = photoPath
        self.timeZone = timeZone
        self.locale = locale
        self.protectedTimeOffSince = protectedTimeOffSince
    }
}

public enum RelationshipType: String, Codable, Sendable, CaseIterable {
    case romantic
    case friendsFamily = "friends_family"
    /// v1 ships the couple type only (P3).
    public static let availableAtLaunch: [RelationshipType] = [.romantic]
}

public enum PairStatus: String, Codable, Sendable { case active, ended }

public struct Pair: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var relationshipType: RelationshipType
    public var status: PairStatus
    public var standardResetMinutes: Int
    public var qrSecretVersion: Int
    public var createdAt: Date

    public init(
        id: UUID, relationshipType: RelationshipType = .romantic, status: PairStatus = .active,
        standardResetMinutes: Int = 30, qrSecretVersion: Int = 1, createdAt: Date
    ) {
        self.id = id
        self.relationshipType = relationshipType
        self.status = status
        self.standardResetMinutes = standardResetMinutes
        self.qrSecretVersion = qrSecretVersion
        self.createdAt = createdAt
    }
}

/// The pair's shared secret for the in-person QR code. Stored in the Keychain only.
public struct QRSecret: Codable, Hashable, Sendable {
    public var pairID: UUID
    public var secret: Data
    public var version: Int

    public init(pairID: UUID, secret: Data, version: Int) {
        self.pairID = pairID
        self.secret = secret
        self.version = version
    }
}

/// The signed-in user's pairing: the pair and the partner.
public struct PairState: Hashable, Sendable {
    public var pair: Pair
    public var partner: UserProfile

    public init(pair: Pair, partner: UserProfile) {
        self.pair = pair
        self.partner = partner
    }
}

public struct Invite: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// 6-character code to read out or type.
    public var code: String
    /// `https://<domain>/i/<token>`.
    public var link: URL
    public var expiresAt: Date

    public init(id: UUID, code: String, link: URL, expiresAt: Date) {
        self.id = id
        self.code = code
        self.link = link
        self.expiresAt = expiresAt
    }

    public static let validity: TimeInterval = 72 * 3600
    public static let codeLength = 6
}

// MARK: - Settings and schedules

/// The notification categories of feature spec §11.
public enum NotificationKind: String, Codable, Sendable, CaseIterable {
    case unlockRequest = "unlock_request"
    case requestResult = "request_result"
    case challengeDone = "challenge_done"
    case kudos
    case scheduleRequest = "schedule_request"
    case minutesExpiring = "minutes_expiring"
    case weeklyReport = "weekly_report"
    case partnerStatus = "partner_status"

    /// Unlock requests and schedule requests can never be muted (§11).
    public var canBeMuted: Bool { self != .unlockRequest && self != .scheduleRequest }
}

public struct NotificationPrefs: Codable, Hashable, Sendable {
    /// Raw values of muted `NotificationKind`s.
    public var muted: Set<String>
    /// Weekly report by email. Off by default; opt-in (decision P24).
    public var weeklyReportEmail: Bool

    public static let weeklyReportEmailDefault = false

    public init(muted: Set<String> = [], weeklyReportEmail: Bool = NotificationPrefs.weeklyReportEmailDefault) {
        self.muted = muted
        self.weeklyReportEmail = weeklyReportEmail
    }

    public func isMuted(_ kind: NotificationKind) -> Bool {
        kind.canBeMuted && muted.contains(kind.rawValue)
    }

    public mutating func setMuted(_ isMuted: Bool, for kind: NotificationKind) {
        guard kind.canBeMuted else { return }
        if isMuted { muted.insert(kind.rawValue) } else { muted.remove(kind.rawValue) }
    }

    enum CodingKeys: String, CodingKey { case muted, weeklyReportEmail }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        muted = Set(try c.decodeIfPresent([String].self, forKey: .muted) ?? [])
        weeklyReportEmail = try c.decodeIfPresent(Bool.self, forKey: .weeklyReportEmail)
            ?? NotificationPrefs.weeklyReportEmailDefault
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(muted.sorted(), forKey: .muted)
        try c.encode(weeklyReportEmail, forKey: .weeklyReportEmail)
    }
}

public struct UserSettings: Codable, Hashable, Sendable {
    public var dailyMaxMinutes: Int
    /// Weekly emergency allowance: 15, 30, 45 or 60 (P14).
    public var emergencyAllowanceMinutes: Int
    public var startingMinutes: Int
    public var notificationPrefs: NotificationPrefs
    /// When onboarding was finished on any phone; a returning user skips what is done (P29).
    public var onboardedAt: Date?

    public init(
        dailyMaxMinutes: Int = MinutesRules.defaultDailyMax,
        emergencyAllowanceMinutes: Int = EmergencyRules.defaultAllowance,
        startingMinutes: Int = MinutesRules.defaultStartingMinutes,
        notificationPrefs: NotificationPrefs = NotificationPrefs(),
        onboardedAt: Date? = nil
    ) {
        self.dailyMaxMinutes = dailyMaxMinutes
        self.emergencyAllowanceMinutes = emergencyAllowanceMinutes
        self.startingMinutes = startingMinutes
        self.notificationPrefs = notificationPrefs
        self.onboardedAt = onboardedAt
    }

    enum CodingKeys: String, CodingKey { case dailyMaxMinutes, emergencyAllowanceMinutes, startingMinutes, notificationPrefs, onboardedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyMaxMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyMaxMinutes) ?? MinutesRules.defaultDailyMax
        emergencyAllowanceMinutes = try c.decodeIfPresent(Int.self, forKey: .emergencyAllowanceMinutes) ?? EmergencyRules.defaultAllowance
        startingMinutes = try c.decodeIfPresent(Int.self, forKey: .startingMinutes) ?? MinutesRules.defaultStartingMinutes
        notificationPrefs = try c.decodeIfPresent(NotificationPrefs.self, forKey: .notificationPrefs) ?? NotificationPrefs()
        onboardedAt = try c.decodeIfPresent(Date.self, forKey: .onboardedAt)
    }
}

public struct ProtectedSchedule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// ISO weekdays on which the schedule starts: 1 = Monday … 7 = Sunday.
    public var weekdays: Set<Int>
    public var startLocal: LocalTime
    /// When `endLocal` is at or before `startLocal` the schedule runs into the next day.
    public var endLocal: LocalTime
    public var enabled: Bool

    public init(
        id: UUID = UUID(), name: String = "", weekdays: Set<Int> = Set(1...7),
        startLocal: LocalTime, endLocal: LocalTime, enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.weekdays = weekdays
        self.startLocal = startLocal
        self.endLocal = endLocal
        self.enabled = enabled
    }

    /// Default protected time: every day 6 PM to 9 AM (P9).
    public static func standard(id: UUID = UUID()) -> ProtectedSchedule {
        ProtectedSchedule(id: id, startLocal: LocalTime(hour: 18), endLocal: LocalTime(hour: 9))
    }

    public var crossesMidnight: Bool { endLocal <= startLocal }
    /// Length of one occurrence in minutes (1…1440).
    public var lengthMinutes: Int {
        let d = endLocal.minutesFromMidnight - startLocal.minutesFromMidnight
        return d > 0 ? d : d + 1440
    }

    enum CodingKeys: String, CodingKey { case id, name, weekdays, startLocal, endLocal, enabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        weekdays = Set(try c.decode([Int].self, forKey: .weekdays))
        startLocal = try c.decode(LocalTime.self, forKey: .startLocal)
        endLocal = try c.decode(LocalTime.self, forKey: .endLocal)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(weekdays.sorted(), forKey: .weekdays)
        try c.encode(startLocal, forKey: .startLocal)
        try c.encode(endLocal, forKey: .endLocal)
        try c.encode(enabled, forKey: .enabled)
    }
}

public enum ChangeRequestStatus: String, Codable, Sendable { case pending, approved, declined, expired }

/// What a looser change asks for. The partner never learns which apps are involved.
public enum ScheduleProposal: Codable, Hashable, Sendable {
    /// New times or days for a schedule (also covers turning it off via `enabled = false`).
    case schedule(ProtectedSchedule)
    /// Remove one of the schedules.
    case removeSchedule
    /// Pause fewer apps. Carries no detail; the new selection stays on the requester's phone.
    case fewerPausedApps

    enum CodingKeys: String, CodingKey { case kind, schedule }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "schedule": self = .schedule(try c.decode(ProtectedSchedule.self, forKey: .schedule))
        case "remove_schedule": self = .removeSchedule
        default: self = .fewerPausedApps
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .schedule(let schedule):
            try c.encode("schedule", forKey: .kind)
            try c.encode(schedule, forKey: .schedule)
        case .removeSchedule: try c.encode("remove_schedule", forKey: .kind)
        case .fewerPausedApps: try c.encode("fewer_paused_apps", forKey: .kind)
        }
    }
}

public struct ScheduleChangeRequest: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var pairID: UUID
    public var requesterID: UUID
    public var scheduleID: UUID?
    public var proposed: ScheduleProposal
    public var status: ChangeRequestStatus
    public var expiresAt: Date
    public var createdAt: Date

    public init(
        id: UUID, pairID: UUID, requesterID: UUID, scheduleID: UUID?, proposed: ScheduleProposal,
        status: ChangeRequestStatus = .pending, expiresAt: Date, createdAt: Date
    ) {
        self.id = id
        self.pairID = pairID
        self.requesterID = requesterID
        self.scheduleID = scheduleID
        self.proposed = proposed
        self.status = status
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

    public static let validity: TimeInterval = 24 * 3600
}

// MARK: - Minutes

public enum LedgerType: String, Codable, Sendable, CaseIterable {
    case startingGrant = "starting_grant"
    case earnChallenge = "earn_challenge"
    case earnKudos = "earn_kudos"
    case spendUnlock = "spend_unlock"
    case emergencyBorrow = "emergency_borrow"
    case debtRepay = "debt_repay"
    case reset
    case expire
    case adminAdjust = "admin_adjust"
    /// Minutes given back when a minutes unlock ends early (P26).
    case unlockRefund = "unlock_refund"
}

public struct MinuteLot: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var userID: UUID
    public var granted: Int
    public var remaining: Int
    public var expiresAt: Date
    public var createdAt: Date
    public var closedAt: Date?

    public init(id: UUID = UUID(), userID: UUID, granted: Int, remaining: Int, expiresAt: Date, createdAt: Date, closedAt: Date? = nil) {
        self.id = id
        self.userID = userID
        self.granted = granted
        self.remaining = remaining
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.closedAt = closedAt
    }
}

public struct LedgerEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var userID: UUID
    public var type: LedgerType
    /// Positive = credit, negative = debit.
    public var minutes: Int
    public var lotID: UUID?
    public var sourceID: UUID?
    public var localDay: LocalDay
    public var createdAt: Date

    public init(id: UUID = UUID(), userID: UUID, type: LedgerType, minutes: Int, lotID: UUID? = nil, sourceID: UUID? = nil, localDay: LocalDay, createdAt: Date) {
        self.id = id
        self.userID = userID
        self.type = type
        self.minutes = minutes
        self.lotID = lotID
        self.sourceID = sourceID
        self.localDay = localDay
        self.createdAt = createdAt
    }
}

/// One person's minutes as shown in the app: open lots, debt and today's spending.
public struct MinutesSummary: Hashable, Sendable {
    public var userID: UUID
    public var lots: [MinuteLot]
    public var debt: Int
    public var spentToday: Int
    public var dailyMax: Int

    public init(userID: UUID, lots: [MinuteLot] = [], debt: Int = 0, spentToday: Int = 0, dailyMax: Int = MinutesRules.defaultDailyMax) {
        self.userID = userID
        self.lots = lots
        self.debt = debt
        self.spentToday = spentToday
        self.dailyMax = dailyMax
    }

    /// Sum of open lots minus debt; negative after an emergency unlock.
    public var balance: Int { lots.reduce(0) { $0 + $1.remaining } - debt }
    public var available: Int { debt > 0 ? 0 : max(0, balance) }
    public var remainingToday: Int { max(0, dailyMax - spentToday) }
}

public enum ResetStatus: String, Codable, Sendable { case pending, accepted, declined, expired }

public struct ResetProposal: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var pairID: UUID
    public var proposerID: UUID
    public var standardMinutes: Int
    public var status: ResetStatus
    public var expiresAt: Date
    public var createdAt: Date

    public init(id: UUID, pairID: UUID, proposerID: UUID, standardMinutes: Int, status: ResetStatus = .pending, expiresAt: Date, createdAt: Date) {
        self.id = id
        self.pairID = pairID
        self.proposerID = proposerID
        self.standardMinutes = standardMinutes
        self.status = status
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }
}

// MARK: - Unlocks

public enum UnlockMethod: String, Codable, Sendable, CaseIterable {
    case qr
    case partnerApproval = "partner_approval"
    case accountabilityCode = "accountability_code"
    case minutes
    case emergency
}

public enum UnlockRequestStatus: String, Codable, Sendable {
    case pending, approved, declined, expired, cancelled, redeemed
}

public struct UnlockRequest: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var pairID: UUID
    public var requesterID: UUID
    public var minutes: Int
    public var reason: String?
    public var status: UnlockRequestStatus
    public var expiresAt: Date
    public var emailSentAt: Date?
    public var createdAt: Date

    public init(
        id: UUID, pairID: UUID, requesterID: UUID, minutes: Int, reason: String? = nil,
        status: UnlockRequestStatus = .pending, expiresAt: Date, emailSentAt: Date? = nil, createdAt: Date
    ) {
        self.id = id
        self.pairID = pairID
        self.requesterID = requesterID
        self.minutes = minutes
        self.reason = reason
        self.status = status
        self.expiresAt = expiresAt
        self.emailSentAt = emailSentAt
        self.createdAt = createdAt
    }
}

public struct Unlock: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var userID: UUID
    public var method: UnlockMethod
    public var minutes: Int
    public var startedAt: Date
    public var endsAt: Date
    public var requestID: UUID?
    public var clientEventID: UUID?
    /// Set when the unlock was ended before its time (P26).
    public var endedEarlyAt: Date?
    /// Whole minutes actually used, once it ended early or (emergency) was settled.
    public var minutesUsed: Int?

    public init(
        id: UUID, userID: UUID, method: UnlockMethod, minutes: Int, startedAt: Date, endsAt: Date,
        requestID: UUID? = nil, clientEventID: UUID? = nil, endedEarlyAt: Date? = nil, minutesUsed: Int? = nil
    ) {
        self.id = id
        self.userID = userID
        self.method = method
        self.minutes = minutes
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.requestID = requestID
        self.clientEventID = clientEventID
        self.endedEarlyAt = endedEarlyAt
        self.minutesUsed = minutesUsed
    }

    public func isActive(at date: Date) -> Bool { startedAt <= date && date < endsAt }

    /// What it counts against an allowance: what was used once known, else its full length.
    public var minutesCounted: Int { minutesUsed ?? minutes }
}

/// An offline QR unlock waiting to be synced (`sync_qr_unlocks`).
public struct QRUnlockEvent: Codable, Hashable, Sendable {
    public var counter: Int64
    public var minutes: Int
    public var startedAt: Date
    public var clientEventID: UUID

    public init(counter: Int64, minutes: Int, startedAt: Date, clientEventID: UUID = UUID()) {
        self.counter = counter
        self.minutes = minutes
        self.startedAt = startedAt
        self.clientEventID = clientEventID
    }
}

// MARK: - Challenges, kudos, streaks

public enum ChallengeCategory: String, Codable, Sendable, CaseIterable {
    case together, kindness
    case offlineFun = "offline_fun"
    case movement
}

public enum ChallengeTier: String, Codable, Sendable { case free, premium }

public enum ChallengeStatus: String, Codable, Sendable {
    case active
    case pendingValueApproval = "pending_value_approval"
    case archived
}

public struct Challenge: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Nil for presets; set for a pair's custom challenges.
    public var pairID: UUID?
    public var createdBy: UUID?
    public var title: String
    public var description: String
    public var minutes: Int
    public var category: ChallengeCategory
    /// Shared challenges grant both partners on one confirmation.
    public var isShared: Bool
    public var tier: ChallengeTier
    public var status: ChallengeStatus
    /// Who proposed the current minute value of a custom challenge; the other partner approves it.
    public var valueProposedBy: UUID?

    public init(
        id: UUID = UUID(), pairID: UUID? = nil, createdBy: UUID? = nil, title: String, description: String = "",
        minutes: Int, category: ChallengeCategory, isShared: Bool = false, tier: ChallengeTier = .premium,
        status: ChallengeStatus = .active, valueProposedBy: UUID? = nil
    ) {
        self.id = id
        self.pairID = pairID
        self.createdBy = createdBy
        self.title = title
        self.description = description
        self.minutes = minutes
        self.category = category
        self.isShared = isShared
        self.tier = tier
        self.status = status
        self.valueProposedBy = valueProposedBy
    }

    public var isCustom: Bool { pairID != nil }
}

public enum CompletionStatus: String, Codable, Sendable {
    case awaitingConfirmation = "awaiting_confirmation"
    case confirmed, expired
}

public struct ChallengeCompletion: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var challengeID: UUID
    public var pairID: UUID
    public var completedBy: UUID
    public var note: String?
    public var photoPath: String?
    public var status: CompletionStatus
    public var confirmedBy: UUID?
    public var expiresAt: Date
    public var createdAt: Date

    public init(
        id: UUID, challengeID: UUID, pairID: UUID, completedBy: UUID, note: String? = nil, photoPath: String? = nil,
        status: CompletionStatus = .awaitingConfirmation, confirmedBy: UUID? = nil, expiresAt: Date, createdAt: Date
    ) {
        self.id = id
        self.challengeID = challengeID
        self.pairID = pairID
        self.completedBy = completedBy
        self.note = note
        self.photoPath = photoPath
        self.status = status
        self.confirmedBy = confirmedBy
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

    public static let validity: TimeInterval = 48 * 3600
}

public struct Kudos: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var pairID: UUID
    public var giverID: UUID
    public var receiverID: UUID
    public var challengeID: UUID?
    public var message: String
    public var minutes: Int
    public var createdAt: Date

    public init(id: UUID, pairID: UUID, giverID: UUID, receiverID: UUID, challengeID: UUID? = nil, message: String, minutes: Int, createdAt: Date) {
        self.id = id
        self.pairID = pairID
        self.giverID = giverID
        self.receiverID = receiverID
        self.challengeID = challengeID
        self.message = message
        self.minutes = minutes
        self.createdAt = createdAt
    }
}

public struct Streak: Codable, Hashable, Sendable {
    public var currentLength: Int
    public var bestLength: Int
    public var lastCountedDay: LocalDay?
    public var startedOn: LocalDay?

    public init(currentLength: Int = 0, bestLength: Int = 0, lastCountedDay: LocalDay? = nil, startedOn: LocalDay? = nil) {
        self.currentLength = currentLength
        self.bestLength = bestLength
        self.lastCountedDay = lastCountedDay
        self.startedOn = startedOn
    }

    /// Milestones that trigger a shared celebration (§9).
    public static let milestones = [3, 7, 14, 30, 60, 100]
    public var isMilestone: Bool { Streak.milestones.contains(currentLength) }
}

// MARK: - Reports

/// One person's numbers for a week (§10).
public struct WeeklyMemberStats: Codable, Hashable, Sendable {
    public var minutesEarned: Int
    public var minutesSpent: Int
    public var minutesExpired: Int
    public var challengesCompleted: Int
    public var requestsSent: Int
    public var requestsApproved: Int
    public var kudosGiven: Int
    public var kudosReceived: Int

    public init(
        minutesEarned: Int = 0, minutesSpent: Int = 0, minutesExpired: Int = 0, challengesCompleted: Int = 0,
        requestsSent: Int = 0, requestsApproved: Int = 0, kudosGiven: Int = 0, kudosReceived: Int = 0
    ) {
        self.minutesEarned = minutesEarned
        self.minutesSpent = minutesSpent
        self.minutesExpired = minutesExpired
        self.challengesCompleted = challengesCompleted
        self.requestsSent = requestsSent
        self.requestsApproved = requestsApproved
        self.kudosGiven = kudosGiven
        self.kudosReceived = kudosReceived
    }
}

public struct WeeklyReport: Codable, Identifiable, Hashable, Sendable {
    public var weekStart: LocalDay
    /// Stats keyed by user id (lowercased UUID string).
    public var members: [String: WeeklyMemberStats]
    public var totalEarnedTogether: Int
    public var sharedChallengesDone: Int
    public var protectedHours: Int
    public var streak: Int
    /// The partner who gave the most kudos this week, if any ("Most generous").
    public var mostGenerousUserID: UUID?

    public var id: LocalDay { weekStart }

    public init(
        weekStart: LocalDay, members: [String: WeeklyMemberStats] = [:], totalEarnedTogether: Int = 0,
        sharedChallengesDone: Int = 0, protectedHours: Int = 0, streak: Int = 0, mostGenerousUserID: UUID? = nil
    ) {
        self.weekStart = weekStart
        self.members = members
        self.totalEarnedTogether = totalEarnedTogether
        self.sharedChallengesDone = sharedChallengesDone
        self.protectedHours = protectedHours
        self.streak = streak
        self.mostGenerousUserID = mostGenerousUserID
    }

    public func stats(for userID: UUID) -> WeeklyMemberStats {
        members[userID.uuidString.lowercased()] ?? WeeklyMemberStats()
    }
}

/// One line of the home screen's activity feed. Only things the app itself creates.
public struct ActivityItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case unlock, emergencyUnlock, requestApproved, requestDeclined, challengeDone, challengeConfirmed
        case kudos, minutesExpired, reset, paired
    }

    public var id: UUID
    public var kind: Kind
    public var actorID: UUID
    public var minutes: Int?
    public var text: String?
    public var date: Date

    public init(id: UUID = UUID(), kind: Kind, actorID: UUID, minutes: Int? = nil, text: String? = nil, date: Date) {
        self.id = id
        self.kind = kind
        self.actorID = actorID
        self.minutes = minutes
        self.text = text
        self.date = date
    }
}

// MARK: - Premium

public enum EntitlementKind: String, Codable, Sendable { case trial, subscription, lifetime }

/// The pair's premium status as read from our backend (not from RevenueCat).
public struct PremiumState: Codable, Hashable, Sendable {
    public var isPremium: Bool
    public var payerID: UUID?
    public var kind: EntitlementKind?
    public var expiresAt: Date?
    /// The 14-day trial is counted once per pair.
    public var trialUsed: Bool
    public var coverageLastChangedAt: Date?

    public init(
        isPremium: Bool = false, payerID: UUID? = nil, kind: EntitlementKind? = nil, expiresAt: Date? = nil,
        trialUsed: Bool = false, coverageLastChangedAt: Date? = nil
    ) {
        self.isPremium = isPremium
        self.payerID = payerID
        self.kind = kind
        self.expiresAt = expiresAt
        self.trialUsed = trialUsed
        self.coverageLastChangedAt = coverageLastChangedAt
    }

    public static let free = PremiumState()
}

/// What the free and premium tiers include (§12).
public enum PremiumRules {
    public static let freeScheduleLimit = 1
    public static let premiumScheduleLimit = 3
    public static let trialDays = 14
    public static let coverageChangeCooldown: TimeInterval = 30 * 24 * 3600

    public static func scheduleLimit(isPremium: Bool) -> Int {
        isPremium ? premiumScheduleLimit : freeScheduleLimit
    }

    /// Challenges a pair can see: free presets always; the premium library and custom ones only with premium.
    /// Custom challenges are hidden, not deleted, on downgrade.
    public static func visibleChallenges(_ all: [Challenge], isPremium: Bool) -> [Challenge] {
        all.filter { $0.status != .archived && (isPremium || ($0.tier == .free && !$0.isCustom)) }
    }

    /// Schedules in effect: all of them with premium, only the first without (extra ones are hidden, not deleted).
    public static func effectiveSchedules(_ all: [ProtectedSchedule], isPremium: Bool) -> [ProtectedSchedule] {
        Array(all.prefix(scheduleLimit(isPremium: isPremium)))
    }
}
