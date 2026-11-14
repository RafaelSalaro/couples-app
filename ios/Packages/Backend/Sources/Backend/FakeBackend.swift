import Core
import Foundation

/// One person's session against a `FakeWorld`.
public final class FakeBackend: Backend, @unchecked Sendable {
    public let world: FakeWorld
    private let lock = NSLock()
    private var session: AuthSession?
    private var offline = false
    /// The identity "Sign in with Apple" resolves to in the fake.
    public let appleIdentity: (email: String, name: String, id: UUID)

    public init(
        world: FakeWorld = FakeWorld(), signedInAs user: UUID? = nil,
        appleIdentity: (email: String, name: String, id: UUID) = ("rafa@example.com", "Rafa", FakeWorld.meID)
    ) {
        self.world = world
        self.appleIdentity = appleIdentity
        if let user, world.hasPerson(user) { session = AuthSession(userID: user) }
    }

    /// Simulates losing the network: calls that need the server fail with `.offline`.
    public func setOffline(_ isOffline: Bool) { lock.withLock { offline = isOffline } }

    private func user() throws -> UUID {
        try lock.withLock {
            if offline { throw BackendError(.offline) }
            guard let session else { throw BackendError(.notSignedIn) }
            return session.userID
        }
    }

    // Auth
    public func currentSession() async -> AuthSession? { lock.withLock { session } }

    public func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> AuthSession {
        let new = world.signIn(email: appleIdentity.email, name: fullName ?? appleIdentity.name, preferredID: appleIdentity.id)
        lock.withLock { session = new }
        return new
    }

    public func sendMagicLink(email: String) async throws {
        guard email.contains("@"), email.contains(".") else { throw BackendError(.invalid) }
        world.recordMagicLink(email)
    }

    /// The link the fake "emails": `scheme://login-callback?email=<address>`.
    public static func magicLink(for email: String, scheme: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "login-callback"
        components.queryItems = [URLQueryItem(name: "email", value: email)]
        return components.url ?? URL(string: "\(scheme)://login-callback")!
    }

    public func completeMagicLink(url: URL) async throws -> AuthSession {
        guard let email = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "email" })?.value,
              world.sentMagicLinks.contains(email) else { throw BackendError(.invalid) }
        let name = email.split(separator: "@").first.map { String($0).capitalized }
        let new = world.signIn(email: email, name: name, preferredID: email == appleIdentity.email ? appleIdentity.id : nil)
        lock.withLock { session = new }
        return new
    }

    public func signOut() async throws { lock.withLock { session = nil } }

    // Profile and settings
    public func fetchProfile() async throws -> UserProfile { try world.profile(user()) }
    public func updateProfile(displayName: String?, timeZone: String?) async throws -> UserProfile {
        try world.updateProfile(user(), displayName: displayName, timeZone: timeZone)
    }
    public func setProtectedTimeOff(_ isOff: Bool) async throws { try world.setProtectedTimeOff(user(), isOff) }
    public func fetchSettings() async throws -> UserSettings { try world.settings(user()) }
    public func updateSettings(_ settings: UserSettings) async throws { try world.updateSettings(user(), settings) }

    // Pairing
    public func fetchPairState() async throws -> PairState? { try world.pairState(user()) }
    public func fetchQRSecret() async throws -> QRSecret? { try world.qrSecret(user()) }
    public func createInvite() async throws -> Invite { try world.createInvite(user()) }
    public func revokeInvite() async throws { world.revokeInvite(try user()) }
    public func acceptInvite(codeOrToken: String) async throws -> PairState { try world.acceptInvite(user(), codeOrToken: codeOrToken) }
    public func unpair() async throws { try world.unpair(user()) }
    public func rotateQRSecret() async throws -> QRSecret { try world.rotateQRSecret(user()) }

    // Schedules
    public func fetchSchedules() async throws -> [ProtectedSchedule] { try world.schedules(user()) }
    public func submitScheduleChange(scheduleID: UUID?, proposal: ScheduleProposal) async throws -> ScheduleChangeOutcome {
        try world.submitScheduleChange(user(), scheduleID: scheduleID, proposal: proposal)
    }
    public func respondScheduleChange(requestID: UUID, approve: Bool) async throws {
        try world.respondScheduleChange(user(), requestID: requestID, approve: approve)
    }
    public func fetchScheduleChangeRequests() async throws -> [ScheduleChangeRequest] { try world.scheduleChangeRequests(user()) }

    // Minutes
    public func fetchMinutes() async throws -> (mine: MinutesSummary, partner: MinutesSummary?) { try world.minutes(user()) }
    public func fetchLedger(limit: Int) async throws -> [LedgerEntry] { try world.ledger(user(), limit: limit) }
    public func proposeReset(standardMinutes: Int) async throws -> ResetProposal { try world.proposeReset(user(), standardMinutes: standardMinutes) }
    public func respondReset(proposalID: UUID, accept: Bool) async throws { try world.respondReset(user(), proposalID: proposalID, accept: accept) }
    public func fetchResetProposals() async throws -> [ResetProposal] { try world.resetProposalsPending(user()) }

    // Unlocks
    public func createUnlockRequest(minutes: Int, reason: String?) async throws -> UnlockRequest {
        try world.createUnlockRequest(user(), minutes: minutes, reason: reason)
    }
    public func respondUnlockRequest(id: UUID, approve: Bool) async throws { try world.respondUnlockRequest(user(), id: id, approve: approve) }
    public func redeemAccountabilityCode(requestID: UUID, code: String) async throws -> Unlock {
        try world.redeemCode(user(), requestID: requestID, code: code)
    }
    public func spendMinutesUnlock(minutes: Int, clientEventID: UUID) async throws -> Unlock {
        try world.spendMinutesUnlock(user(), minutes: minutes, clientEventID: clientEventID)
    }
    public func emergencyUnlock(clientEventID: UUID) async throws -> Unlock { try world.emergencyUnlock(user(), clientEventID: clientEventID) }
    public func syncQRUnlocks(_ events: [QRUnlockEvent]) async throws { try world.syncQRUnlocks(user(), events) }
    public func fetchPendingUnlockRequests() async throws -> [UnlockRequest] { try world.pendingUnlockRequests(user()) }
    public func fetchUnlock(requestID: UUID) async throws -> Unlock? {
        _ = try user()
        return world.unlock(forRequest: requestID)
    }
    public func lastEmergencyUnlock() async throws -> Date? { world.lastEmergency(try user()) }

    // Challenges and kudos
    public func fetchChallenges() async throws -> [Challenge] { try world.challenges(user()) }
    public func completeChallenge(id: UUID, note: String?) async throws -> ChallengeCompletion { try world.completeChallenge(user(), id: id, note: note) }
    public func confirmCompletion(id: UUID) async throws { try world.confirmCompletion(user(), id: id) }
    public func fetchCompletions() async throws -> [ChallengeCompletion] { try world.completionsRecent(user()) }
    public func createCustomChallenge(title: String, description: String, minutes: Int, category: ChallengeCategory, isShared: Bool) async throws -> Challenge {
        try world.createCustomChallenge(user(), title: title, description: description, minutes: minutes, category: category, isShared: isShared)
    }
    public func respondChallengeValue(challengeID: UUID, approve: Bool, counterMinutes: Int?) async throws -> Challenge {
        try world.respondChallengeValue(user(), challengeID: challengeID, approve: approve, counterMinutes: counterMinutes)
    }
    public func giveKudos(minutes: Int, message: String, challengeID: UUID?) async throws -> Kudos {
        try world.giveKudos(user(), minutes: minutes, message: message, challengeID: challengeID)
    }
    public func fetchKudos(limit: Int) async throws -> [Kudos] { try world.kudosRecent(user(), limit: limit) }

    // Streak, reports, activity, premium
    public func fetchStreak() async throws -> Streak { try world.streak(user()) }
    public func fetchWeeklyReports() async throws -> [WeeklyReport] { try world.weeklyReports(user()) }
    public func fetchActivity(limit: Int) async throws -> [ActivityItem] { try world.activityFeed(user(), limit: limit) }
    public func fetchPremium() async throws -> PremiumState { try world.premium(user()) }

    // Account
    public func exportMyData() async throws -> Data { try world.exportData(user()) }
    public func deleteAccount() async throws {
        try world.deleteAccount(user())
        lock.withLock { session = nil }
    }
    public func registerPushToken(_ token: String, sandbox: Bool) async throws { world.registerPushToken(try user(), token) }
    public func logEvent(_ name: String, props: [String: String]) async { world.log(name) }

    public func events() -> AsyncStream<BackendEvent> {
        guard let id = lock.withLock({ session?.userID }) else { return AsyncStream { $0.finish() } }
        return world.listen(id)
    }
}

/// A scripted partner for the Simulator and UI tests: answers what the user sends and can
/// start things on its own, the way a real partner's phone would.
public final class FakePartnerBot: Sendable {
    public struct Behavior: Sendable, Equatable {
        public enum Answer: String, Sendable { case yes, no, silent }
        public var unlockRequests: Answer = .yes
        public var completions: Answer = .yes
        public var scheduleChanges: Answer = .yes
        public var resets: Answer = .yes
        public var challengeValues: Answer = .yes
        /// Accepts the user's invite as soon as one exists.
        public var acceptsInvite = true
        public var delay: Duration = .milliseconds(1200)

        public init() {}
    }

    /// Things the partner does unprompted, a moment after launch.
    public enum Action: String, Sendable, CaseIterable {
        case sendKudos, askUnlock, completeChallenge, proposeReset, proposeScheduleChange, proposeCustomChallenge, unpair, emergencyUnlock, turnProtectionOff
    }

    public let backend: FakeBackend
    public let behavior: Behavior
    private let userBackend: FakeBackend

    /// - Parameters:
    ///   - backend: the partner's own session.
    ///   - userBackend: the app user's session (to find the invite the user creates).
    public init(backend: FakeBackend, userBackend: FakeBackend, behavior: Behavior = Behavior()) {
        self.backend = backend
        self.userBackend = userBackend
        self.behavior = behavior
    }

    /// Starts reacting. Runs until the returned task is cancelled.
    @discardableResult
    public func start(actions: [Action] = []) -> Task<Void, Never> {
        Task { [self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.react() }
                if self.behavior.acceptsInvite { group.addTask { await self.watchForInvite() } }
                group.addTask {
                    for action in actions {
                        try? await Task.sleep(for: self.behavior.delay)
                        await self.perform(action)
                    }
                }
            }
        }
    }

    private func watchForInvite() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(400))
            guard let me = await backend.currentSession()?.userID, let user = await userBackend.currentSession()?.userID,
                  (try? backend.world.pairState(me)) == nil, let invite = backend.world.openInvite(user) else { continue }
            try? await Task.sleep(for: behavior.delay)
            _ = try? await backend.acceptInvite(codeOrToken: invite.code)
        }
    }

    private func react() async {
        for await event in backend.events() {
            guard let me = await backend.currentSession()?.userID else { return }
            switch event {
            case .unlockRequestChanged(let request, _) where request.status == .pending && request.requesterID != me:
                await answer(behavior.unlockRequests) { try await self.backend.respondUnlockRequest(id: request.id, approve: $0) }
            case .completionChanged(let completion) where completion.status == .awaitingConfirmation && completion.completedBy != me:
                if behavior.completions == .yes {
                    try? await Task.sleep(for: behavior.delay)
                    try? await backend.confirmCompletion(id: completion.id)
                }
            case .scheduleChangeChanged(let request) where request.status == .pending && request.requesterID != me:
                await answer(behavior.scheduleChanges) { try await self.backend.respondScheduleChange(requestID: request.id, approve: $0) }
            case .resetProposalChanged(let proposal) where proposal.status == .pending && proposal.proposerID != me:
                await answer(behavior.resets) { try await self.backend.respondReset(proposalID: proposal.id, accept: $0) }
            case .challengeChanged(let challenge) where challenge.status == .pendingValueApproval && challenge.valueProposedBy != me:
                await answer(behavior.challengeValues) {
                    _ = try await self.backend.respondChallengeValue(challengeID: challenge.id, approve: $0, counterMinutes: $0 ? nil : max(5, challenge.minutes - 5))
                }
            default:
                break
            }
        }
    }

    private func answer(_ answer: Behavior.Answer, _ respond: @escaping @Sendable (Bool) async throws -> Void) async {
        guard answer != .silent else { return }
        try? await Task.sleep(for: behavior.delay)
        try? await respond(answer == .yes)
    }

    public func perform(_ action: Action) async {
        switch action {
        case .sendKudos:
            _ = try? await backend.giveKudos(minutes: 10, message: "You made me laugh today", challengeID: nil)
        case .askUnlock:
            _ = try? await backend.createUnlockRequest(minutes: 30, reason: "Reply to a client")
        case .completeChallenge:
            if let challenge = try? await backend.fetchChallenges().first(where: { $0.tier == .free && !$0.isShared }) {
                _ = try? await backend.completeChallenge(id: challenge.id, note: nil)
            }
        case .proposeReset:
            _ = try? await backend.proposeReset(standardMinutes: MinutesRules.standardResetMinutes)
        case .proposeScheduleChange:
            if var schedule = try? await backend.fetchSchedules().first {
                schedule.startLocal = LocalTime(hour: 19)
                _ = try? await backend.submitScheduleChange(scheduleID: schedule.id, proposal: .schedule(schedule))
            }
        case .proposeCustomChallenge:
            _ = try? await backend.createCustomChallenge(title: "Fix the bike together", description: "", minutes: 30, category: .together, isShared: true)
        case .unpair:
            try? await backend.unpair()
        case .emergencyUnlock:
            _ = try? await backend.emergencyUnlock(clientEventID: UUID())
        case .turnProtectionOff:
            try? await backend.setProtectedTimeOff(true)
        }
    }
}
