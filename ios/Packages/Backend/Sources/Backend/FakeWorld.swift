import Core
import Foundation

/// An in-memory stand-in for the whole server: every user, pair, ledger and request.
/// It mirrors the rules of `docs/03-feature-spec.md` and `docs/05-data-model-and-api.md`
/// so the app can run in the Simulator and in UI tests without Supabase.
/// Several `FakeBackend` sessions (one per simulated person) can share one world.
public final class FakeWorld: @unchecked Sendable {
    public static let meID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    public static let partnerID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    /// The accountability code the fake always issues, so tests can type it.
    public static let fixedAccountabilityCode = "246810"

    struct Person {
        var profile: UserProfile
        var email: String
        var settings = UserSettings()
        var ledger: MinutesLedger
        var schedules: [ProtectedSchedule] = []
        var pushEnabled = true
        var entitlement: (kind: EntitlementKind, expiresAt: Date?)?
        var pushTokens: [String] = []
    }

    struct PairRecord {
        var pair: Pair
        var members: [UUID]
        var secret: Data
        var streak = Streak()
        var payerID: UUID?
        var coverageChangedAt: Date?
        var trialUsed = false
        var usedCounters: Set<Int64> = []
    }

    struct InviteRecord {
        var invite: Invite
        var token: String
        var inviterID: UUID
        var open = true
    }

    private let lock = NSRecursiveLock()
    public let now: NowProvider
    public let websiteDomain: String

    private var people: [UUID: Person] = [:]
    private var pairs: [UUID: PairRecord] = [:]
    private var invites: [InviteRecord] = []
    private var unlockRequests: [UnlockRequest] = []
    private var codeAttempts: [UUID: Int] = [:]
    private var unlocks: [Unlock] = []
    private var challenges: [Challenge] = FakeWorld.presetChallenges
    private var completions: [ChallengeCompletion] = []
    private var kudos: [Kudos] = []
    private var scheduleRequests: [ScheduleChangeRequest] = []
    private var resetProposals: [ResetProposal] = []
    private var activity: [(pairID: UUID?, item: ActivityItem)] = []
    private var pastReports: [UUID: [WeeklyReport]] = [:]
    private var listeners: [UUID: [UUID: AsyncStream<BackendEvent>.Continuation]] = [:]
    public private(set) var loggedEvents: [String] = []
    public private(set) var sentMagicLinks: [String] = []
    public private(set) var deletedUsers: Set<UUID> = []

    public init(now: @escaping NowProvider = { Date() }, websiteDomain: String = "example.com") {
        self.now = now
        self.websiteDomain = websiteDomain
    }

    // MARK: Seeding

    @discardableResult
    /// Marks onboarding as finished on the "server" (settings.onboarded_at), as for an account
    /// that has been set up before: signing back in then skips it (P29).
    public func seedOnboarded(_ user: UUID, at date: Date = Date()) {
        lock.withLock { people[user]?.settings.onboardedAt = date }
    }

    public func addPerson(id: UUID = UUID(), name: String?, email: String, timeZone: TimeZone = .current) -> UUID {
        lock.withLock {
            people[id] = Person(
                profile: UserProfile(id: id, displayName: name, timeZone: timeZone.identifier),
                email: email, ledger: MinutesLedger(userID: id), schedules: [.standard()]
            )
            return id
        }
    }

    public func hasPerson(_ id: UUID) -> Bool { lock.withLock { people[id] != nil } }
    public func personID(email: String) -> UUID? {
        lock.withLock { people.first { $0.value.email.lowercased() == email.lowercased() }?.key }
    }

    /// Pairs two people directly (seeding), with starting grants.
    @discardableResult
    public func seedPair(_ a: UUID, _ b: UUID, streak: Int = 0) -> UUID {
        lock.withLock {
            let id = makePair(a, b)
            pairs[id]?.streak = Streak(currentLength: streak, bestLength: streak)
            return id
        }
    }

    public func seedInvite(from inviter: UUID, code: String, token: String = "seedtoken") {
        lock.withLock {
            let t = now()
            let invite = Invite(id: UUID(), code: code, link: inviteLink(token), expiresAt: t.addingTimeInterval(Invite.validity))
            invites.append(InviteRecord(invite: invite, token: token, inviterID: inviter))
        }
    }

    public func seedGrant(_ minutes: Int, to user: UUID, type: LedgerType = .earnChallenge, at date: Date? = nil) {
        lock.withLock {
            guard let cal = calendar(user) else { return }
            people[user]?.ledger.grant(minutes, type: type, now: date ?? now(), calendar: cal)
        }
    }

    public func seedSchedules(_ schedules: [ProtectedSchedule], for user: UUID) {
        lock.withLock { people[user]?.schedules = schedules }
    }

    public func seedPastReports(for pair: UUID, _ reports: [WeeklyReport]) {
        lock.withLock { pastReports[pair] = reports }
    }

    public func setPushEnabled(_ enabled: Bool, for user: UUID) { lock.withLock { people[user]?.pushEnabled = enabled } }

    /// Simulates the RevenueCat webhook: the user bought (or lost) an entitlement.
    public func setEntitlement(_ kind: EntitlementKind?, for user: UUID, expiresAt: Date? = nil) {
        lock.withLock {
            if let kind {
                people[user]?.entitlement = (kind, expiresAt)
                if let pairID = pairID(of: user), pairs[pairID]?.payerID == nil {
                    pairs[pairID]?.payerID = user
                    pairs[pairID]?.coverageChangedAt = now()
                }
                if kind == .trial, let pairID = pairID(of: user) { pairs[pairID]?.trialUsed = true }
            } else {
                people[user]?.entitlement = nil
            }
            emit(.premiumChanged, to: Array(Set([user] + partners(of: user))))
        }
    }

    /// Simulates buying a product: the yearly plan starts with the 14-day trial if the pair
    /// (or the person) has not used it; otherwise it is a paid year. Lifetime never expires.
    public func simulatePurchase(yearly: Bool, by user: UUID) {
        let trialUsed = lock.withLock { premiumState(user).trialUsed }
        if !yearly {
            setEntitlement(.lifetime, for: user)
        } else if trialUsed {
            setEntitlement(.subscription, for: user, expiresAt: now().addingTimeInterval(365 * 86400))
        } else {
            setEntitlement(.trial, for: user, expiresAt: now().addingTimeInterval(Double(PremiumRules.trialDays) * 86400))
        }
    }

    // MARK: Helpers

    private func calendar(_ user: UUID) -> Calendar? {
        guard let zone = people[user].map({ TimeZone(identifier: $0.profile.timeZone) ?? .current }) else { return nil }
        return .gregorian(in: zone)
    }

    private func inviteLink(_ token: String) -> URL { URL(string: "https://\(websiteDomain)/i/\(token)")! }

    private func pairID(of user: UUID) -> UUID? {
        pairs.first { $0.value.pair.status == .active && $0.value.members.contains(user) }?.key
    }

    private func partners(of user: UUID) -> [UUID] {
        guard let id = pairID(of: user) else { return [] }
        return pairs[id]?.members.filter { $0 != user } ?? []
    }

    private func requirePerson(_ user: UUID) throws -> Person {
        guard let person = people[user] else { throw BackendError(.notSignedIn) }
        return person
    }

    private func requirePair(_ user: UUID) throws -> (id: UUID, partner: UUID) {
        guard let id = pairID(of: user), let partner = partners(of: user).first else { throw BackendError(.notPaired) }
        return (id, partner)
    }

    private func isPremium(_ user: UUID) -> Bool { premiumState(user).isPremium }

    private func entitlementActive(_ user: UUID) -> Bool {
        guard let e = people[user]?.entitlement else { return false }
        return e.expiresAt.map { $0 > now() } ?? true
    }

    private func premiumState(_ user: UUID) -> PremiumState {
        if let id = pairID(of: user), let record = pairs[id] {
            if let payer = record.payerID, record.members.contains(payer), entitlementActive(payer), let e = people[payer]?.entitlement {
                return PremiumState(isPremium: true, payerID: payer, kind: e.kind, expiresAt: e.expiresAt, trialUsed: record.trialUsed, coverageLastChangedAt: record.coverageChangedAt)
            }
            return PremiumState(trialUsed: record.trialUsed)
        }
        if entitlementActive(user), let e = people[user]?.entitlement {
            return PremiumState(isPremium: true, payerID: user, kind: e.kind, expiresAt: e.expiresAt, trialUsed: e.kind == .trial)
        }
        return .free
    }

    private func makePair(_ a: UUID, _ b: UUID) -> UUID {
        let t = now()
        let id = UUID()
        var record = PairRecord(pair: Pair(id: id, createdAt: t), members: [a, b], secret: Data((0..<20).map { _ in UInt8.random(in: 0...255) }))
        for member in [a, b] where entitlementActive(member) && record.payerID == nil {
            record.payerID = member
            record.coverageChangedAt = t
        }
        pairs[id] = record
        for member in [a, b] {
            guard let cal = calendar(member), let start = people[member]?.settings.startingMinutes else { continue }
            people[member]?.ledger.grant(start, type: .startingGrant, now: t, calendar: cal)
        }
        activity.append((id, ActivityItem(kind: .paired, actorID: a, date: t)))
        return id
    }

    private func emit(_ event: BackendEvent, to users: [UUID]) {
        for user in users {
            for continuation in (listeners[user] ?? [:]).values { continuation.yield(event) }
        }
    }

    private func both(_ user: UUID) -> [UUID] { [user] + partners(of: user) }

    /// Lazily applies everything the server's cron jobs do: expiring requests, proposals, invites and lots.
    private func sweep() {
        let t = now()
        for index in unlockRequests.indices where unlockRequests[index].status == .pending {
            let request = unlockRequests[index]
            if request.expiresAt <= t {
                unlockRequests[index].status = .expired
                emit(.unlockRequestChanged(unlockRequests[index], unlock: nil), to: both(request.requesterID))
            } else if request.emailSentAt == nil, t.timeIntervalSince(request.createdAt) >= UnlockRules.emailFallbackDelay {
                unlockRequests[index].emailSentAt = t
                emit(.unlockRequestChanged(unlockRequests[index], unlock: nil), to: [request.requesterID])
            }
        }
        for index in completions.indices where completions[index].status == .awaitingConfirmation && completions[index].expiresAt <= t {
            completions[index].status = .expired
        }
        for index in scheduleRequests.indices where scheduleRequests[index].status == .pending && scheduleRequests[index].expiresAt <= t {
            scheduleRequests[index].status = .expired
        }
        for index in resetProposals.indices where resetProposals[index].status == .pending && resetProposals[index].expiresAt <= t {
            resetProposals[index].status = .expired
        }
        for index in invites.indices where invites[index].open && invites[index].invite.expiresAt <= t {
            invites[index].open = false
        }
        for id in people.keys {
            guard let cal = calendar(id) else { continue }
            people[id]?.ledger.expire(now: t, calendar: cal)
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        sweep()
        return try body()
    }

    // MARK: Listening

    func listen(_ user: UUID) -> AsyncStream<BackendEvent> {
        let token = UUID()
        return AsyncStream { continuation in
            lock.withLock { listeners[user, default: [:]][token] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { self.listeners[user]?[token] = nil }
            }
        }
    }

    // MARK: Auth, profile, settings

    public func signIn(email: String, name: String?, preferredID: UUID? = nil) -> AuthSession {
        locked {
            if let id = personIDLocked(email: email) { return AuthSession(userID: id, email: email) }
            let id = preferredID.flatMap { people[$0] == nil ? $0 : nil } ?? UUID()
            people[id] = Person(profile: UserProfile(id: id, displayName: name), email: email, ledger: MinutesLedger(userID: id), schedules: [.standard()])
            return AuthSession(userID: id, email: email)
        }
    }

    private func personIDLocked(email: String) -> UUID? {
        people.first { $0.value.email.lowercased() == email.lowercased() }?.key
    }

    func recordMagicLink(_ email: String) { lock.withLock { sentMagicLinks.append(email) } }

    func profile(_ user: UUID) throws -> UserProfile { try locked { try requirePerson(user).profile } }

    func updateProfile(_ user: UUID, displayName: String?, timeZone: String?) throws -> UserProfile {
        try locked {
            _ = try requirePerson(user)
            if let displayName { people[user]?.profile.displayName = String(displayName.prefix(60)) }
            if let timeZone { people[user]?.profile.timeZone = timeZone }
            emit(.pairChanged, to: partners(of: user))
            return people[user]!.profile
        }
    }

    func setProtectedTimeOff(_ user: UUID, _ isOff: Bool) throws {
        try locked {
            let was = try requirePerson(user).profile.protectedTimeOffSince != nil
            guard was != isOff else { return }
            people[user]?.profile.protectedTimeOffSince = isOff ? now() : nil
            if isOff, let id = pairID(of: user) { breakStreak(id) }
            emit(.partnerStatusChanged, to: partners(of: user))
        }
    }

    func settings(_ user: UUID) throws -> UserSettings { try locked { try requirePerson(user).settings } }

    func updateSettings(_ user: UUID, _ settings: UserSettings) throws {
        try locked {
            _ = try requirePerson(user)
            guard MinutesRules.dailyMaxRange.contains(settings.dailyMaxMinutes),
                  MinutesRules.startingMinutesRange.contains(settings.startingMinutes) else { throw BackendError(.invalid) }
            people[user]?.settings = settings
            emit(.minutesChanged, to: both(user))
        }
    }

    // MARK: Pairing

    public func pairState(_ user: UUID) throws -> PairState? {
        try locked {
            _ = try requirePerson(user)
            guard let id = pairID(of: user), let record = pairs[id], let partner = partners(of: user).first,
                  let profile = people[partner]?.profile else { return nil }
            return PairState(pair: record.pair, partner: profile)
        }
    }

    public func qrSecret(_ user: UUID) throws -> QRSecret? {
        try locked {
            _ = try requirePerson(user)
            guard let id = pairID(of: user), let record = pairs[id] else { return nil }
            return QRSecret(pairID: id, secret: record.secret, version: record.pair.qrSecretVersion)
        }
    }

    func createInvite(_ user: UUID) throws -> Invite {
        try locked {
            _ = try requirePerson(user)
            guard pairID(of: user) == nil else { throw BackendError(.alreadyPaired) }
            for index in invites.indices where invites[index].inviterID == user { invites[index].open = false }
            let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
            let code = String((0..<Invite.codeLength).map { _ in alphabet.randomElement()! })
            let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let invite = Invite(id: UUID(), code: code, link: inviteLink(token), expiresAt: now().addingTimeInterval(Invite.validity))
            invites.append(InviteRecord(invite: invite, token: token, inviterID: user))
            return invite
        }
    }

    public func openInvite(_ user: UUID) -> Invite? {
        locked { invites.last { $0.inviterID == user && $0.open }?.invite }
    }

    func revokeInvite(_ user: UUID) {
        locked { for index in invites.indices where invites[index].inviterID == user { invites[index].open = false } }
    }

    func acceptInvite(_ user: UUID, codeOrToken: String) throws -> PairState {
        try locked {
            _ = try requirePerson(user)
            guard pairID(of: user) == nil else { throw BackendError(.alreadyPaired) }
            let key = codeOrToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let index = invites.firstIndex(where: { $0.invite.code == key.uppercased() || $0.token == key }) else {
                throw BackendError(.invalid)
            }
            guard invites[index].open else { throw BackendError(.expired) }
            let inviter = invites[index].inviterID
            guard inviter != user else { throw BackendError(.invalid) }
            guard pairID(of: inviter) == nil else { throw BackendError(.alreadyPaired) }
            invites[index].open = false
            let id = makePair(inviter, user)
            emit(.pairChanged, to: [inviter, user])
            emit(.minutesChanged, to: [inviter, user])
            return PairState(pair: pairs[id]!.pair, partner: people[inviter]!.profile)
        }
    }

    func unpair(_ user: UUID) throws {
        try locked {
            let (id, partner) = try requirePair(user)
            let t = now()
            pairs[id]?.pair.status = .ended
            // Active minutes reset to zero (history kept); open items are cancelled.
            for member in [user, partner] {
                guard let cal = calendar(member) else { continue }
                people[member]?.ledger.reset(to: 0, now: t, calendar: cal)
            }
            for index in unlockRequests.indices where unlockRequests[index].pairID == id && unlockRequests[index].status == .pending {
                unlockRequests[index].status = .cancelled
            }
            for index in completions.indices where completions[index].pairID == id && completions[index].status == .awaitingConfirmation {
                completions[index].status = .expired
            }
            for index in scheduleRequests.indices where scheduleRequests[index].pairID == id && scheduleRequests[index].status == .pending {
                scheduleRequests[index].status = .expired
            }
            for index in resetProposals.indices where resetProposals[index].pairID == id && resetProposals[index].status == .pending {
                resetProposals[index].status = .expired
            }
            emit(.pairChanged, to: [user, partner])
            emit(.minutesChanged, to: [user, partner])
            emit(.premiumChanged, to: [user, partner])
        }
    }

    func rotateQRSecret(_ user: UUID) throws -> QRSecret {
        try locked {
            let (id, partner) = try requirePair(user)
            pairs[id]?.secret = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
            pairs[id]?.pair.qrSecretVersion += 1
            emit(.qrSecretRotated, to: [user, partner])
            return QRSecret(pairID: id, secret: pairs[id]!.secret, version: pairs[id]!.pair.qrSecretVersion)
        }
    }

    // MARK: Schedules

    func schedules(_ user: UUID) throws -> [ProtectedSchedule] { try locked { try requirePerson(user).schedules } }

    private func applying(_ proposal: ScheduleProposal, scheduleID: UUID?, to current: [ProtectedSchedule]) -> [ProtectedSchedule] {
        var result = current
        switch proposal {
        case .schedule(let schedule):
            if let index = result.firstIndex(where: { $0.id == (scheduleID ?? schedule.id) }) {
                result[index] = schedule
            } else {
                result.append(schedule)
            }
        case .removeSchedule:
            result.removeAll { $0.id == scheduleID }
        case .fewerPausedApps:
            break
        }
        return result
    }

    func submitScheduleChange(_ user: UUID, scheduleID: UUID?, proposal: ScheduleProposal) throws -> ScheduleChangeOutcome {
        try locked {
            let person = try requirePerson(user)
            let proposed = applying(proposal, scheduleID: scheduleID, to: person.schedules)
            guard proposed.count <= PremiumRules.scheduleLimit(isPremium: isPremium(user)) || proposed.count <= person.schedules.count else {
                throw BackendError(.premiumRequired)
            }
            let change: ScheduleChange = proposal == .fewerPausedApps ? .looser : ScheduleChange.classify(from: person.schedules, to: proposed)
            let paired = pairID(of: user)
            if ScheduleChange.appliesImmediately(change, isPaired: paired != nil) {
                people[user]?.schedules = proposed
                return .applied(proposed)
            }
            let t = now()
            let request = ScheduleChangeRequest(
                id: UUID(), pairID: paired!, requesterID: user, scheduleID: scheduleID, proposed: proposal,
                expiresAt: t.addingTimeInterval(ScheduleChangeRequest.validity), createdAt: t
            )
            // A newer request for the same thing replaces the older pending one.
            for index in scheduleRequests.indices
            where scheduleRequests[index].requesterID == user && scheduleRequests[index].status == .pending && scheduleRequests[index].scheduleID == scheduleID {
                scheduleRequests[index].status = .expired
            }
            scheduleRequests.append(request)
            emit(.scheduleChangeChanged(request), to: partners(of: user))
            return .pending(request)
        }
    }

    func respondScheduleChange(_ user: UUID, requestID: UUID, approve: Bool) throws {
        try locked {
            guard let index = scheduleRequests.firstIndex(where: { $0.id == requestID }) else { throw BackendError(.invalid) }
            let request = scheduleRequests[index]
            guard request.status == .pending else { throw BackendError(.expired) }
            guard request.requesterID != user, partners(of: user).contains(request.requesterID) else { throw BackendError(.notPartner) }
            scheduleRequests[index].status = approve ? .approved : .declined
            if approve, let current = people[request.requesterID]?.schedules {
                people[request.requesterID]?.schedules = applying(request.proposed, scheduleID: request.scheduleID, to: current)
                if case .schedule(let s) = request.proposed, !s.enabled, let id = pairID(of: user) { breakStreak(id) }
            }
            emit(.scheduleChangeChanged(scheduleRequests[index]), to: [request.requesterID, user])
        }
    }

    func scheduleChangeRequests(_ user: UUID) throws -> [ScheduleChangeRequest] {
        try locked {
            _ = try requirePerson(user)
            guard let id = pairID(of: user) else { return [] }
            return scheduleRequests.filter { $0.pairID == id && $0.status == .pending }
        }
    }

    // MARK: Minutes

    private func summary(_ user: UUID) -> MinutesSummary? {
        settleEmergencies(user)
        guard let person = people[user], let cal = calendar(user) else { return nil }
        return person.ledger.summary(now: now(), calendar: cal, dailyMax: person.settings.dailyMaxMinutes)
    }

    func minutes(_ user: UUID) throws -> (mine: MinutesSummary, partner: MinutesSummary?) {
        try locked {
            _ = try requirePerson(user)
            return (summary(user)!, partners(of: user).first.flatMap(summary))
        }
    }

    func ledger(_ user: UUID, limit: Int) throws -> [LedgerEntry] {
        try locked { Array(try requirePerson(user).ledger.entries.reversed().prefix(limit)) }
    }

    func proposeReset(_ user: UUID, standardMinutes: Int) throws -> ResetProposal {
        try locked {
            let (id, partner) = try requirePair(user)
            guard MinutesRules.startingMinutesRange.contains(standardMinutes) else { throw BackendError(.invalid) }
            for index in resetProposals.indices where resetProposals[index].pairID == id && resetProposals[index].status == .pending {
                resetProposals[index].status = .expired
            }
            let t = now()
            let proposal = ResetProposal(id: UUID(), pairID: id, proposerID: user, standardMinutes: standardMinutes, expiresAt: t.addingTimeInterval(MinutesRules.resetProposalValidity), createdAt: t)
            resetProposals.append(proposal)
            emit(.resetProposalChanged(proposal), to: [partner])
            return proposal
        }
    }

    func respondReset(_ user: UUID, proposalID: UUID, accept: Bool) throws {
        try locked {
            guard let index = resetProposals.firstIndex(where: { $0.id == proposalID }) else { throw BackendError(.invalid) }
            let proposal = resetProposals[index]
            guard proposal.status == .pending else { throw BackendError(.expired) }
            guard proposal.proposerID != user, partners(of: user).contains(proposal.proposerID) else { throw BackendError(.notPartner) }
            resetProposals[index].status = accept ? .accepted : .declined
            if accept {
                let t = now()
                for member in [user, proposal.proposerID] {
                    guard let cal = calendar(member) else { continue }
                    people[member]?.ledger.reset(to: proposal.standardMinutes, source: proposal.id, now: t, calendar: cal)
                }
                activity.append((proposal.pairID, ActivityItem(kind: .reset, actorID: user, minutes: proposal.standardMinutes, date: t)))
                emit(.minutesChanged, to: [user, proposal.proposerID])
            }
            emit(.resetProposalChanged(resetProposals[index]), to: [user, proposal.proposerID])
        }
    }

    func resetProposalsPending(_ user: UUID) throws -> [ResetProposal] {
        try locked {
            _ = try requirePerson(user)
            guard let id = pairID(of: user) else { return [] }
            return resetProposals.filter { $0.pairID == id && $0.status == .pending }
        }
    }

    // MARK: Unlocks

    // MARK: Emergency allowance (P14) and ending early (P26)

    /// Emergency sessions that ran to their end borrow the minutes they lasted (the server's
    /// settle_emergency_unlocks). Caller holds the lock.
    private func settleEmergencies(_ user: UUID) {
        let t = now()
        guard let cal = calendar(user) else { return }
        for index in unlocks.indices where unlocks[index].userID == user && unlocks[index].method == .emergency
            && unlocks[index].minutesUsed == nil && unlocks[index].endsAt <= t {
            unlocks[index].minutesUsed = unlocks[index].minutes
            people[user]?.ledger.borrow(unlocks[index].minutes, unlockID: unlocks[index].id, now: unlocks[index].endsAt, calendar: cal)
        }
    }

    private func emergencyStatusLocked(_ user: UUID) -> EmergencyAllowance {
        let allowance = people[user]?.settings.emergencyAllowanceMinutes ?? EmergencyRules.defaultAllowance
        return EmergencyRules.status(allowance: allowance, sessions: unlocks.filter { $0.userID == user }, now: now())
    }

    func emergencyStatus(_ user: UUID) throws -> EmergencyAllowance {
        try locked {
            _ = try requirePerson(user)
            settleEmergencies(user)
            return emergencyStatusLocked(user)
        }
    }

    func endUnlockEarly(_ user: UUID, unlockID: UUID) throws -> Unlock {
        try locked {
            guard let index = unlocks.firstIndex(where: { $0.id == unlockID && $0.userID == user }) else { throw BackendError(.invalid) }
            let unlock = unlocks[index]
            if unlock.endedEarlyAt != nil { return unlock } // ending again changes nothing
            let t = now()
            guard unlock.isActive(at: t), let cal = calendar(user) else { throw BackendError(.notActive) }
            var used = min(unlock.minutes, UnlockRules.minutesUsed(from: unlock.startedAt, to: t))
            switch unlock.method {
            case .emergency:
                people[user]?.ledger.borrow(used, unlockID: unlock.id, now: t, calendar: cal)
            case .minutes:
                let refunded = people[user]?.ledger.refund(UnlockRules.unusedWholeMinutes(endsAt: unlock.endsAt, now: t), unlockID: unlock.id, now: t, calendar: cal) ?? 0
                used = unlock.minutes - refunded
            default:
                break
            }
            unlocks[index].endedEarlyAt = t
            unlocks[index].endsAt = t
            unlocks[index].minutesUsed = used
            emit(.minutesChanged, to: both(user))
            return unlocks[index]
        }
    }

    private func recordUnlock(_ user: UUID, method: UnlockMethod, minutes: Int, startedAt: Date? = nil, requestID: UUID? = nil, clientEventID: UUID? = nil, id: UUID? = nil) -> Unlock {
        let start = startedAt ?? now()
        let unlock = Unlock(id: id ?? UUID(), userID: user, method: method, minutes: minutes, startedAt: start, endsAt: start.addingTimeInterval(Double(minutes) * 60), requestID: requestID, clientEventID: clientEventID)
        unlocks.append(unlock)
        activity.append((pairID(of: user), ActivityItem(kind: method == .emergency ? .emergencyUnlock : .unlock, actorID: user, minutes: minutes, date: start)))
        return unlock
    }

    private func validLength(_ minutes: Int) -> Bool {
        minutes >= UnlockRules.minimumLength && minutes % UnlockRules.step == 0
    }

    func createUnlockRequest(_ user: UUID, minutes: Int, reason: String?) throws -> UnlockRequest {
        try locked {
            _ = try requirePerson(user)
            guard let id = pairID(of: user), let partner = partners(of: user).first else { throw BackendError(.partnerMissing) }
            guard validLength(minutes), (reason?.count ?? 0) <= 140 else { throw BackendError(.invalid) }
            let t = now()
            let recent = unlockRequests.filter { $0.requesterID == user && t.timeIntervalSince($0.createdAt) < 3600 }
            guard recent.count < UnlockRules.maxRequestsPerHour else { throw BackendError(.rateLimited) }
            let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            let request = UnlockRequest(
                id: UUID(), pairID: id, requesterID: user, minutes: minutes, reason: (trimmed?.isEmpty ?? true) ? nil : trimmed,
                expiresAt: t.addingTimeInterval(UnlockRules.requestValidity),
                // With notifications off the email (and its code) goes out right away.
                emailSentAt: people[partner]?.pushEnabled == false ? t : nil, createdAt: t
            )
            unlockRequests.append(request)
            emit(.unlockRequestChanged(request, unlock: nil), to: [partner])
            return request
        }
    }

    func respondUnlockRequest(_ user: UUID, id: UUID, approve: Bool) throws {
        try locked {
            guard let index = unlockRequests.firstIndex(where: { $0.id == id }) else { throw BackendError(.invalid) }
            let request = unlockRequests[index]
            guard request.requesterID != user, partners(of: user).contains(request.requesterID) else { throw BackendError(.notPartner) }
            guard request.status == .pending else { throw BackendError(.expired) }
            unlockRequests[index].status = approve ? .approved : .declined
            var unlock: Unlock?
            if approve {
                unlock = recordUnlock(request.requesterID, method: .partnerApproval, minutes: request.minutes, requestID: id)
            }
            activity.append((request.pairID, ActivityItem(kind: approve ? .requestApproved : .requestDeclined, actorID: user, minutes: request.minutes, date: now())))
            emit(.unlockRequestChanged(unlockRequests[index], unlock: unlock), to: [request.requesterID, user])
        }
    }

    func redeemCode(_ user: UUID, requestID: UUID, code: String) throws -> Unlock {
        try locked {
            guard let index = unlockRequests.firstIndex(where: { $0.id == requestID && $0.requesterID == user }) else { throw BackendError(.invalid) }
            guard unlockRequests[index].status == .pending else { throw BackendError(.expired) }
            guard codeAttempts[requestID, default: 0] < UnlockRules.maxCodeAttempts else { throw BackendError(.tooManyAttempts) }
            guard unlockRequests[index].emailSentAt != nil, code == FakeWorld.fixedAccountabilityCode else {
                codeAttempts[requestID, default: 0] += 1
                throw BackendError(codeAttempts[requestID, default: 0] >= UnlockRules.maxCodeAttempts ? .tooManyAttempts : .invalid)
            }
            unlockRequests[index].status = .redeemed
            let unlock = recordUnlock(user, method: .accountabilityCode, minutes: unlockRequests[index].minutes, requestID: requestID)
            emit(.unlockRequestChanged(unlockRequests[index], unlock: unlock), to: both(user))
            return unlock
        }
    }

    func spendMinutesUnlock(_ user: UUID, minutes: Int, clientEventID: UUID) throws -> Unlock {
        try locked {
            let person = try requirePerson(user)
            if let existing = unlocks.first(where: { $0.clientEventID == clientEventID }) { return existing }
            guard validLength(minutes), let cal = calendar(user) else { throw BackendError(.invalid) }
            settleEmergencies(user)
            let unlockID = UUID()
            do {
                try people[user]?.ledger.spend(minutes, dailyMax: person.settings.dailyMaxMinutes, unlockID: unlockID, now: now(), calendar: cal)
            } catch let error as MinutesError {
                switch error {
                case .insufficient: throw BackendError(.insufficient)
                case .overDailyMax: throw BackendError(.overDailyMax)
                case .inDebt: throw BackendError(.inDebt)
                }
            }
            let unlock = recordUnlock(user, method: .minutes, minutes: minutes, clientEventID: clientEventID, id: unlockID)
            emit(.minutesChanged, to: both(user))
            return unlock
        }
    }

    /// Starts an emergency session for what is left of the weekly allowance (P14). Nothing is
    /// borrowed now; the minutes used are borrowed when it ends. A running session is returned.
    func emergencyUnlock(_ user: UUID, clientEventID: UUID) throws -> Unlock {
        try locked {
            _ = try requirePerson(user)
            if let existing = unlocks.first(where: { $0.clientEventID == clientEventID }) { return existing }
            settleEmergencies(user)
            let t = now()
            if let running = unlocks.first(where: { $0.userID == user && $0.method == .emergency && $0.endedEarlyAt == nil && $0.isActive(at: t) }) {
                return running
            }
            let status = emergencyStatusLocked(user)
            guard !status.isUsedUp else { throw BackendError(.allowanceUsedUp) }
            let unlock = recordUnlock(user, method: .emergency, minutes: status.remaining, clientEventID: clientEventID)
            if let id = pairID(of: user) { breakStreak(id) } // once per day: breaking again the same day changes nothing
            emit(.minutesChanged, to: both(user))
            emit(.partnerStatusChanged, to: partners(of: user))
            return unlock
        }
    }

    func syncQRUnlocks(_ user: UUID, _ events: [QRUnlockEvent]) throws {
        try locked {
            let (id, _) = try requirePair(user)
            var duplicate = false
            for event in events {
                if unlocks.contains(where: { $0.clientEventID == event.clientEventID }) { continue } // idempotent
                if pairs[id]?.usedCounters.contains(event.counter) == true {
                    duplicate = true
                    continue
                }
                pairs[id]?.usedCounters.insert(event.counter)
                _ = recordUnlock(user, method: .qr, minutes: event.minutes, startedAt: event.startedAt, clientEventID: event.clientEventID)
            }
            if duplicate { throw BackendError(.duplicateCounter) }
        }
    }

    func pendingUnlockRequests(_ user: UUID) throws -> [UnlockRequest] {
        try locked {
            _ = try requirePerson(user)
            guard let id = pairID(of: user) else { return [] }
            return unlockRequests.filter { $0.pairID == id && $0.status == .pending }
        }
    }

    func unlock(forRequest id: UUID) -> Unlock? { locked { unlocks.first { $0.requestID == id } } }
    public func unlocks(of user: UUID) -> [Unlock] { locked { unlocks.filter { $0.userID == user } } }

    // MARK: Challenges and kudos

    func challenges(_ user: UUID) throws -> [Challenge] {
        try locked {
            _ = try requirePerson(user)
            let id = pairID(of: user)
            return challenges.filter { $0.pairID == nil || $0.pairID == id }
        }
    }

    func completeChallenge(_ user: UUID, id: UUID, note: String?) throws -> ChallengeCompletion {
        try locked {
            let (pair, partner) = try requirePair(user)
            guard let challenge = challenges.first(where: { $0.id == id && ($0.pairID == nil || $0.pairID == pair) }), challenge.status == .active else {
                throw BackendError(.invalid)
            }
            guard challenge.tier == .free || isPremium(user) else { throw BackendError(.premiumRequired) }
            if let open = completions.first(where: { $0.challengeID == id && $0.completedBy == user && $0.status == .awaitingConfirmation }) {
                return open
            }
            let t = now()
            let completion = ChallengeCompletion(id: UUID(), challengeID: id, pairID: pair, completedBy: user, note: note, expiresAt: t.addingTimeInterval(ChallengeCompletion.validity), createdAt: t)
            completions.append(completion)
            activity.append((pair, ActivityItem(kind: .challengeDone, actorID: user, minutes: challenge.minutes, text: challenge.title, date: t)))
            emit(.completionChanged(completion), to: [partner])
            return completion
        }
    }

    func confirmCompletion(_ user: UUID, id: UUID) throws {
        try locked {
            guard let index = completions.firstIndex(where: { $0.id == id }) else { throw BackendError(.invalid) }
            let completion = completions[index]
            guard completion.completedBy != user, partners(of: user).contains(completion.completedBy) else { throw BackendError(.notPartner) }
            guard completion.status == .awaitingConfirmation else { throw BackendError(.expired) }
            guard let challenge = challenges.first(where: { $0.id == completion.challengeID }) else { throw BackendError(.invalid) }
            let t = now()
            completions[index].status = .confirmed
            completions[index].confirmedBy = user
            // Shared challenges grant both partners on one confirmation.
            for member in challenge.isShared ? [completion.completedBy, user] : [completion.completedBy] {
                guard let cal = calendar(member) else { continue }
                people[member]?.ledger.grant(challenge.minutes, type: .earnChallenge, source: completion.id, now: t, calendar: cal)
            }
            activity.append((completion.pairID, ActivityItem(kind: .challengeConfirmed, actorID: completion.completedBy, minutes: challenge.minutes, text: challenge.title, date: t)))
            emit(.completionChanged(completions[index]), to: [completion.completedBy, user])
            emit(.minutesChanged, to: [completion.completedBy, user])
        }
    }

    func completionsRecent(_ user: UUID) throws -> [ChallengeCompletion] {
        try locked {
            _ = try requirePerson(user)
            guard let id = pairID(of: user) else { return [] }
            return completions.filter { $0.pairID == id }.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func createCustomChallenge(_ user: UUID, title: String, description: String, minutes: Int, category: ChallengeCategory, isShared: Bool) throws -> Challenge {
        try locked {
            let (pair, partner) = try requirePair(user)
            guard isPremium(user) else { throw BackendError(.premiumRequired) }
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...80).contains(title.count), description.count <= 280, MinutesRules.customChallengeRange.contains(minutes) else {
                throw BackendError(.invalid)
            }
            let challenge = Challenge(pairID: pair, createdBy: user, title: title, description: description, minutes: minutes, category: category, isShared: isShared, tier: .premium, status: .pendingValueApproval, valueProposedBy: user)
            challenges.append(challenge)
            emit(.challengeChanged(challenge), to: [partner])
            return challenge
        }
    }

    func respondChallengeValue(_ user: UUID, challengeID: UUID, approve: Bool, counterMinutes: Int?) throws -> Challenge {
        try locked {
            let (pair, partner) = try requirePair(user)
            guard let index = challenges.firstIndex(where: { $0.id == challengeID && $0.pairID == pair }),
                  challenges[index].status == .pendingValueApproval else { throw BackendError(.invalid) }
            // Only the partner who did not propose the current value can answer it.
            guard challenges[index].valueProposedBy != user else { throw BackendError(.notPartner) }
            if approve {
                challenges[index].status = .active
            } else if let counterMinutes {
                guard MinutesRules.customChallengeRange.contains(counterMinutes) else { throw BackendError(.invalid) }
                challenges[index].minutes = counterMinutes
                challenges[index].valueProposedBy = user
            } else {
                challenges[index].status = .archived
            }
            emit(.challengeChanged(challenges[index]), to: [partner, user])
            return challenges[index]
        }
    }

    func giveKudos(_ user: UUID, minutes: Int, message: String, challengeID: UUID?) throws -> Kudos {
        try locked {
            let (pair, partner) = try requirePair(user)
            guard isPremium(user) else { throw BackendError(.premiumRequired) }
            guard MinutesRules.kudosRange.contains(minutes), message.count <= 140, let cal = calendar(user) else { throw BackendError(.invalid) }
            let t = now()
            let today = LocalDay(t, calendar: cal)
            let givenToday = kudos.filter { $0.giverID == user && LocalDay($0.createdAt, calendar: cal) == today }.reduce(0) { $0 + $1.minutes }
            guard givenToday + minutes <= MinutesRules.kudosDailyCap else { throw BackendError(.dailyCap) }
            let item = Kudos(id: UUID(), pairID: pair, giverID: user, receiverID: partner, challengeID: challengeID, message: message, minutes: minutes, createdAt: t)
            kudos.append(item)
            if let partnerCal = calendar(partner) {
                people[partner]?.ledger.grant(minutes, type: .earnKudos, source: item.id, now: t, calendar: partnerCal)
            }
            activity.append((pair, ActivityItem(kind: .kudos, actorID: user, minutes: minutes, text: message, date: t)))
            emit(.kudosReceived(item), to: [partner])
            emit(.minutesChanged, to: [user, partner])
            return item
        }
    }

    func kudosRecent(_ user: UUID, limit: Int) throws -> [Kudos] {
        try locked {
            _ = try requirePerson(user)
            guard let id = pairID(of: user) else { return [] }
            return Array(kudos.filter { $0.pairID == id }.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
        }
    }

    // MARK: Streak, reports, activity, premium

    private func breakStreak(_ pair: UUID) {
        guard var streak = pairs[pair]?.streak else { return }
        streak.currentLength = 0
        streak.startedOn = nil
        pairs[pair]?.streak = streak
        emit(.streakChanged(streak), to: pairs[pair]?.members ?? [])
    }

    /// Simulates the nightly rollover counting one more day.
    public func advanceStreak(for user: UUID) {
        locked {
            guard let id = pairID(of: user), var streak = pairs[id]?.streak else { return }
            streak.currentLength += 1
            streak.bestLength = max(streak.bestLength, streak.currentLength)
            pairs[id]?.streak = streak
            emit(.streakChanged(streak), to: pairs[id]?.members ?? [])
        }
    }

    func streak(_ user: UUID) throws -> Streak {
        try locked {
            _ = try requirePerson(user)
            return pairID(of: user).flatMap { pairs[$0]?.streak } ?? Streak()
        }
    }

    func weeklyReports(_ user: UUID) throws -> [WeeklyReport] {
        try locked {
            _ = try requirePerson(user)
            guard let id = pairID(of: user), let record = pairs[id], let cal = calendar(user) else { return [] }
            let t = now()
            let weekStart = cal.dateInterval(of: .weekOfYear, for: t)?.start ?? cal.startOfDay(for: t)
            var report = WeeklyReport(weekStart: LocalDay(weekStart, calendar: cal), streak: record.streak.currentLength)
            for member in record.members {
                let entries = (people[member]?.ledger.entries ?? []).filter { $0.createdAt >= weekStart }
                var stats = WeeklyMemberStats()
                stats.minutesEarned = entries.filter { [.earnChallenge, .earnKudos, .debtRepay].contains($0.type) }.reduce(0) { $0 + $1.minutes }
                stats.minutesSpent = -entries.filter { $0.type == .spendUnlock }.reduce(0) { $0 + $1.minutes }
                stats.minutesExpired = -entries.filter { $0.type == .expire }.reduce(0) { $0 + $1.minutes }
                stats.challengesCompleted = completions.filter { $0.completedBy == member && $0.status == .confirmed && $0.createdAt >= weekStart }.count
                let sent = unlockRequests.filter { $0.requesterID == member && $0.createdAt >= weekStart }
                stats.requestsSent = sent.count
                stats.requestsApproved = sent.filter { $0.status == .approved || $0.status == .redeemed }.count
                stats.kudosGiven = kudos.filter { $0.giverID == member && $0.createdAt >= weekStart }.count
                stats.kudosReceived = kudos.filter { $0.receiverID == member && $0.createdAt >= weekStart }.count
                report.members[member.uuidString.lowercased()] = stats
                report.totalEarnedTogether += stats.minutesEarned
            }
            report.sharedChallengesDone = completions.filter { c in
                c.pairID == id && c.status == .confirmed && c.createdAt >= weekStart && challenges.first { $0.id == c.challengeID }?.isShared == true
            }.count
            let days = max(1, (cal.dateComponents([.day], from: weekStart, to: t).day ?? 0) + 1)
            let weeklyMinutes = record.members.reduce(0) { total, member in
                total + ScheduleChange.coverage(people[member]?.schedules ?? []).filter { $0 }.count
            }
            report.protectedHours = weeklyMinutes * days / 7 / 60
            let given = record.members.map { ($0, report.stats(for: $0).kudosGiven) }.max { $0.1 < $1.1 }
            if let given, given.1 > 0 { report.mostGenerousUserID = given.0 }
            return [report] + (pastReports[id] ?? [])
        }
    }

    func activityFeed(_ user: UUID, limit: Int) throws -> [ActivityItem] {
        try locked {
            _ = try requirePerson(user)
            let id = pairID(of: user)
            let mine = activity.enumerated().filter { ($0.element.pairID != nil && $0.element.pairID == id) || $0.element.item.actorID == user }
            // Newest first; entries with the same timestamp keep reverse insertion order.
            let sorted = mine.sorted { ($0.element.item.date, $0.offset) > ($1.element.item.date, $1.offset) }
            return Array(sorted.map(\.element.item).prefix(limit))
        }
    }

    func premium(_ user: UUID) throws -> PremiumState {
        try locked {
            _ = try requirePerson(user)
            return premiumState(user)
        }
    }

    // MARK: Account

    func exportData(_ user: UUID) throws -> Data {
        try locked {
            let person = try requirePerson(user)
            struct Export: Encodable {
                var profile: UserProfile
                var email: String
                var settings: UserSettings
                var schedules: [ProtectedSchedule]
                var ledger: [LedgerEntry]
                var unlocks: [Unlock]
                var unlockRequests: [UnlockRequest]
                var completions: [ChallengeCompletion]
                var kudos: [Kudos]
            }
            let export = Export(
                profile: person.profile, email: person.email, settings: person.settings, schedules: person.schedules,
                ledger: person.ledger.entries, unlocks: unlocks.filter { $0.userID == user },
                unlockRequests: unlockRequests.filter { $0.requesterID == user },
                completions: completions.filter { $0.completedBy == user },
                kudos: kudos.filter { $0.giverID == user || $0.receiverID == user }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return (try? encoder.encode(export)) ?? Data("{}".utf8)
        }
    }

    func deleteAccount(_ user: UUID) throws {
        try locked {
            _ = try requirePerson(user)
            if pairID(of: user) != nil { try unpair(user) }
            people[user] = nil
            invites.removeAll { $0.inviterID == user }
            deletedUsers.insert(user)
        }
    }

    func registerPushToken(_ user: UUID, _ token: String) { locked { people[user]?.pushTokens.append(token) } }
    func log(_ name: String) { lock.withLock { loggedEvents.append(name) } }

    // MARK: Seed content

    /// The 5 free presets (identical to `supabase/seeds/00_preset_challenges.sql`) and a sample of the premium library.
    static let presetChallenges: [Challenge] = {
        func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-9000-%012d", n))! }
        return [
            Challenge(id: id(1), title: "Phone-free dinner together", description: "Share a meal with both phones out of reach.", minutes: 20, category: .together, isShared: true, tier: .free),
            Challenge(id: id(2), title: "Walk together without phones", description: "Take a walk, just the two of you. Leave the phones at home or in a pocket.", minutes: 20, category: .movement, isShared: true, tier: .free),
            Challenge(id: id(3), title: "Make your partner laugh today", description: "A joke, a silly dance, an old story. Anything that gets a real laugh.", minutes: 10, category: .kindness, tier: .free),
            Challenge(id: id(4), title: "Cook something together", description: "Pick a recipe and make it side by side.", minutes: 25, category: .together, isShared: true, tier: .free),
            Challenge(id: id(5), title: "Write your partner a note", description: "A few handwritten lines left where they will find them.", minutes: 10, category: .kindness, tier: .free),
            Challenge(id: id(6), title: "Breakfast at the table", description: "Sit down for breakfast together, even a quick one.", minutes: 15, category: .together, isShared: true),
            Challenge(id: id(7), title: "Board game night", description: "Pick a game and play a full round.", minutes: 30, category: .offlineFun, isShared: true),
            Challenge(id: id(8), title: "Stretch together", description: "Ten minutes of stretching, side by side.", minutes: 10, category: .movement, isShared: true),
            Challenge(id: id(9), title: "Bring them a coffee", description: "Make or bring your partner their favorite drink.", minutes: 10, category: .kindness),
            Challenge(id: id(10), title: "Read aloud to each other", description: "A chapter, a poem or an article you liked.", minutes: 20, category: .offlineFun, isShared: true),
        ]
    }()
}
