import Core
import Foundation

public struct AuthSession: Equatable, Sendable {
    public var userID: UUID
    public var email: String?

    public init(userID: UUID, email: String? = nil) {
        self.userID = userID
        self.email = email
    }
}

/// Live changes pushed by the server (Realtime channel `pair:<pair_id>` and pushes).
public enum BackendEvent: Equatable, Sendable {
    case minutesChanged
    case unlockRequestChanged(UnlockRequest, unlock: Unlock?)
    case completionChanged(ChallengeCompletion)
    case challengeChanged(Challenge)
    case kudosReceived(Kudos)
    case scheduleChangeChanged(ScheduleChangeRequest)
    case resetProposalChanged(ResetProposal)
    case streakChanged(Streak)
    /// Paired, or the partner ended the pairing.
    case pairChanged
    case premiumChanged
    /// The partner's protected time went off or came back on, or they used an emergency unlock.
    case partnerStatusChanged
    case qrSecretRotated
}

public enum ScheduleChangeOutcome: Equatable, Sendable {
    /// Stricter (or unpaired): applied right away.
    case applied([ProtectedSchedule])
    /// Looser: waiting for the partner, for up to 24 hours.
    case pending(ScheduleChangeRequest)
}

/// Everything the app asks of the server, following `docs/05-data-model-and-api.md`.
/// `SupabaseBackend` talks to Supabase; `FakeBackend` keeps everything in memory for the
/// Simulator and UI tests.
public protocol Backend: Sendable {
    // Auth
    func currentSession() async -> AuthSession?
    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> AuthSession
    func sendMagicLink(email: String) async throws
    func completeMagicLink(url: URL) async throws -> AuthSession
    func signOut() async throws

    // Profile and settings
    func fetchProfile() async throws -> UserProfile
    func updateProfile(displayName: String?, timeZone: String?) async throws -> UserProfile
    /// Reports that protected time is off (permission revoked or turned off) or back on. The partner sees a neutral status.
    func setProtectedTimeOff(_ isOff: Bool) async throws
    func fetchSettings() async throws -> UserSettings
    func updateSettings(_ settings: UserSettings) async throws

    // Pairing
    func fetchPairState() async throws -> PairState?
    func fetchQRSecret() async throws -> QRSecret?
    func createInvite() async throws -> Invite
    func revokeInvite() async throws
    func acceptInvite(codeOrToken: String) async throws -> PairState
    func unpair() async throws
    func rotateQRSecret() async throws -> QRSecret

    // Schedules
    func fetchSchedules() async throws -> [ProtectedSchedule]
    /// `scheduleID` nil with a `.schedule` proposal adds a schedule.
    func submitScheduleChange(scheduleID: UUID?, proposal: ScheduleProposal) async throws -> ScheduleChangeOutcome
    func respondScheduleChange(requestID: UUID, approve: Bool) async throws
    func fetchScheduleChangeRequests() async throws -> [ScheduleChangeRequest]

    // Minutes
    func fetchMinutes() async throws -> (mine: MinutesSummary, partner: MinutesSummary?)
    func fetchLedger(limit: Int) async throws -> [LedgerEntry]
    func proposeReset(standardMinutes: Int) async throws -> ResetProposal
    func respondReset(proposalID: UUID, accept: Bool) async throws
    func fetchResetProposals() async throws -> [ResetProposal]

    // Unlocks
    func createUnlockRequest(minutes: Int, reason: String?) async throws -> UnlockRequest
    func respondUnlockRequest(id: UUID, approve: Bool) async throws
    func redeemAccountabilityCode(requestID: UUID, code: String) async throws -> Unlock
    func spendMinutesUnlock(minutes: Int, clientEventID: UUID) async throws -> Unlock
    /// Starts an emergency session for the remaining weekly allowance (P14); `allowance_used_up` when none is left.
    func emergencyUnlock(clientEventID: UUID) async throws -> Unlock
    /// Ends a running unlock early (P26): emergency borrows only the minutes used, minutes are refunded, others just end.
    func endUnlockEarly(unlockID: UUID) async throws -> Unlock
    func syncQRUnlocks(_ events: [QRUnlockEvent]) async throws
    func fetchPendingUnlockRequests() async throws -> [UnlockRequest]
    func fetchUnlock(requestID: UUID) async throws -> Unlock?
    /// The weekly emergency allowance: used, left and when it renews (P14).
    func emergencyStatus() async throws -> EmergencyAllowance

    // Challenges and kudos
    func fetchChallenges() async throws -> [Challenge]
    func completeChallenge(id: UUID, note: String?) async throws -> ChallengeCompletion
    func confirmCompletion(id: UUID) async throws
    func fetchCompletions() async throws -> [ChallengeCompletion]
    func createCustomChallenge(title: String, description: String, minutes: Int, category: ChallengeCategory, isShared: Bool) async throws -> Challenge
    func respondChallengeValue(challengeID: UUID, approve: Bool, counterMinutes: Int?) async throws -> Challenge
    func giveKudos(minutes: Int, message: String, challengeID: UUID?) async throws -> Kudos
    func fetchKudos(limit: Int) async throws -> [Kudos]

    // Streak, reports, activity
    func fetchStreak() async throws -> Streak
    /// Newest first; the first element is the current week.
    func fetchWeeklyReports() async throws -> [WeeklyReport]
    func fetchActivity(limit: Int) async throws -> [ActivityItem]

    // Premium
    func fetchPremium() async throws -> PremiumState

    // Account
    func exportMyData() async throws -> Data
    func deleteAccount() async throws
    func registerPushToken(_ token: String, sandbox: Bool) async throws
    /// Product event without personal content. Never throws; analytics must not break a flow.
    func logEvent(_ name: String, props: [String: String]) async

    // Realtime
    func events() -> AsyncStream<BackendEvent>
}
