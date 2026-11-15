import Core
import Foundation
import Testing
@testable import Backend

/// A controllable clock.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
    func set(_ date: Date) { lock.withLock { current = date } }
}

let zone = TimeZone(identifier: "America/New_York")!
func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    Calendar.gregorian(in: zone).date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

/// Two seeded users: "me" (Rafa) and the partner (Ana).
struct Fixture {
    let clock = TestClock(at(2026, 11, 10, 20, 0))
    let world: FakeWorld
    let me: FakeBackend
    let ana: FakeBackend

    init(paired: Bool = true, premium: Bool = false) {
        let clock = clock
        world = FakeWorld(now: { clock.now })
        world.addPerson(id: FakeWorld.meID, name: "Rafa", email: "rafa@example.com", timeZone: zone)
        world.addPerson(id: FakeWorld.partnerID, name: "Ana", email: "ana@example.com", timeZone: zone)
        if paired { world.seedPair(FakeWorld.meID, FakeWorld.partnerID, streak: 4) }
        if premium { world.setEntitlement(.subscription, for: FakeWorld.meID) }
        me = FakeBackend(world: world, signedInAs: FakeWorld.meID)
        ana = FakeBackend(world: world, signedInAs: FakeWorld.partnerID)
    }

    func code(of error: Error?) -> BackendError.Code? { (error as? BackendError)?.code }
}

func expectCode(_ code: BackendError.Code, _ body: () async throws -> Void) async {
    do {
        try await body()
        Issue.record("Expected \(code) but the call succeeded")
    } catch let error as BackendError {
        #expect(error.code == code)
    } catch {
        Issue.record("Unexpected error \(error)")
    }
}

@Suite struct FakeAuthAndPairingTests {
    @Test func appleSignInCreatesTheUserOnce() async throws {
        let backend = FakeBackend()
        #expect(await backend.currentSession() == nil)
        let session = try await backend.signInWithApple(idToken: "t", nonce: nil, fullName: nil)
        #expect(session.userID == FakeWorld.meID)
        #expect(try await backend.fetchProfile().displayName == "Rafa")
        try await backend.signOut()
        #expect(await backend.currentSession() == nil)
        let again = try await backend.signInWithApple(idToken: "t", nonce: nil, fullName: nil)
        #expect(again.userID == session.userID)
    }

    @Test func magicLink() async throws {
        let backend = FakeBackend()
        await expectCode(.invalid) { try await backend.sendMagicLink(email: "nope") }
        try await backend.sendMagicLink(email: "sam@example.com")
        let url = FakeBackend.magicLink(for: "sam@example.com", scheme: "couplesapp")
        #expect(DeepLink.parse(url, scheme: "couplesapp", domain: "example.com") == .authCallback(url))
        let session = try await backend.completeMagicLink(url: url)
        #expect(session.email == "sam@example.com")
        await expectCode(.invalid) {
            _ = try await FakeBackend().completeMagicLink(url: FakeBackend.magicLink(for: "other@example.com", scheme: "couplesapp"))
        }
    }

    @Test func signedOutCallsFail() async {
        await expectCode(.notSignedIn) { _ = try await FakeBackend().fetchProfile() }
    }

    @Test func inviteByCodeAndLinkPairsBothWithStartingMinutes() async throws {
        let f = Fixture(paired: false)
        #expect(try await f.me.fetchPairState() == nil)
        let invite = try await f.me.createInvite()
        #expect(invite.code.count == 6)
        #expect(invite.link.absoluteString.hasPrefix("https://example.com/i/"))
        #expect(invite.expiresAt == f.clock.now.addingTimeInterval(72 * 3600))
        let state = try await f.ana.acceptInvite(codeOrToken: invite.code.lowercased())
        #expect(state.partner.displayName == "Rafa")
        #expect(try await f.me.fetchPairState()?.partner.displayName == "Ana")
        // Starting balance granted once at pairing (default 30) and visible to both.
        let minutes = try await f.me.fetchMinutes()
        #expect(minutes.mine.balance == 30 && minutes.partner?.balance == 30)
        // The pair shares one QR secret.
        let mine = try await f.me.fetchQRSecret(), theirs = try await f.ana.fetchQRSecret()
        #expect(mine != nil && mine == theirs && mine?.secret.count == 20)
        // Inviting while paired is disabled.
        await expectCode(.alreadyPaired) { _ = try await f.me.createInvite() }
    }

    @Test func linkTokenWorksAndInvitesExpireOrRevoke() async throws {
        let f = Fixture(paired: false)
        let invite = try await f.me.createInvite()
        let token = invite.link.lastPathComponent
        f.clock.advance(72 * 3600)
        await expectCode(.expired) { _ = try await f.ana.acceptInvite(codeOrToken: token) }
        let second = try await f.me.createInvite()
        try await f.me.revokeInvite()
        await expectCode(.expired) { _ = try await f.ana.acceptInvite(codeOrToken: second.code) }
        await expectCode(.invalid) { _ = try await f.ana.acceptInvite(codeOrToken: "ZZZZZZ") }
        let third = try await f.me.createInvite()
        await expectCode(.invalid) { _ = try await f.me.acceptInvite(codeOrToken: third.code) }
        _ = try await f.ana.acceptInvite(codeOrToken: third.link.lastPathComponent)
        #expect(try await f.ana.fetchPairState() != nil)
    }

    /// §3: unpair is instant and unilateral; minutes reset to zero (history kept); open requests cancelled.
    @Test func unpairEffects() async throws {
        let f = Fixture()
        let request = try await f.me.createUnlockRequest(minutes: 30, reason: nil)
        var events = f.me.events().makeAsyncIterator()
        try await f.ana.unpair()
        #expect(await events.next() == .pairChanged)
        #expect(try await f.me.fetchPairState() == nil)
        #expect(try await f.me.fetchMinutes().mine.balance == 0)
        #expect(try await f.me.fetchMinutes().partner == nil)
        #expect(!(try await f.me.fetchLedger(limit: 10)).isEmpty)
        await expectCode(.notPartner) { try await f.ana.respondUnlockRequest(id: request.id, approve: true) }
        await expectCode(.notPaired) { try await f.me.unpair() }
        // Protected time stays on each phone.
        #expect(try await f.me.fetchSchedules().count == 1)
        // Re-pairing starts fresh.
        let invite = try await f.me.createInvite()
        _ = try await f.ana.acceptInvite(codeOrToken: invite.code)
        #expect(try await f.me.fetchStreak().currentLength == 0)
    }

    @Test func rotatingTheSecretReachesBoth() async throws {
        let f = Fixture()
        let before = try await f.me.fetchQRSecret()
        var events = f.ana.events().makeAsyncIterator()
        let rotated = try await f.me.rotateQRSecret()
        #expect(rotated.version == 2 && rotated.secret != before?.secret)
        #expect(await events.next() == .qrSecretRotated)
        #expect(try await f.ana.fetchQRSecret() == rotated)
    }
}

@Suite struct FakeUnlockTests {
    @Test func askPartnerApproved() async throws {
        let f = Fixture()
        var partnerEvents = f.ana.events().makeAsyncIterator()
        var myEvents = f.me.events().makeAsyncIterator()
        let request = try await f.me.createUnlockRequest(minutes: 30, reason: " Reply to a client ")
        #expect(request.reason == "Reply to a client")
        #expect(request.expiresAt == f.clock.now.addingTimeInterval(300))
        #expect(await partnerEvents.next() == .unlockRequestChanged(request, unlock: nil))
        #expect(try await f.ana.fetchPendingUnlockRequests() == [request])
        try await f.ana.respondUnlockRequest(id: request.id, approve: true)
        guard case .unlockRequestChanged(let updated, let unlock)? = await myEvents.next() else {
            Issue.record("No approval event")
            return
        }
        #expect(updated.status == .approved && unlock?.method == .partnerApproval && unlock?.minutes == 30)
        // No minutes spent.
        #expect(try await f.me.fetchMinutes().mine.balance == 30)
        #expect(try await f.me.fetchUnlock(requestID: request.id) == unlock)
    }

    @Test func letsWaitAndOnlyThePartnerCanAnswer() async throws {
        let f = Fixture()
        let request = try await f.me.createUnlockRequest(minutes: 15, reason: nil)
        await expectCode(.notPartner) { try await f.me.respondUnlockRequest(id: request.id, approve: true) }
        try await f.ana.respondUnlockRequest(id: request.id, approve: false)
        #expect(try await f.me.fetchUnlock(requestID: request.id) == nil)
        await expectCode(.expired) { try await f.ana.respondUnlockRequest(id: request.id, approve: true) }
    }

    /// 07 §3: request expires at 5 minutes; approval after expiry fails.
    @Test func approvalAfterExpiryFails() async throws {
        let f = Fixture()
        let request = try await f.me.createUnlockRequest(minutes: 30, reason: nil)
        f.clock.advance(299)
        #expect(try await f.ana.fetchPendingUnlockRequests().count == 1)
        f.clock.advance(1)
        await expectCode(.expired) { try await f.ana.respondUnlockRequest(id: request.id, approve: true) }
        #expect(try await f.ana.fetchPendingUnlockRequests().isEmpty)
    }

    /// 07 §3: accountability code is single use with 5 attempts max.
    @Test func accountabilityCode() async throws {
        let f = Fixture()
        let request = try await f.me.createUnlockRequest(minutes: 30, reason: nil)
        // No email yet: the code cannot work.
        await expectCode(.invalid) { _ = try await f.me.redeemAccountabilityCode(requestID: request.id, code: FakeWorld.fixedAccountabilityCode) }
        f.clock.advance(120)
        #expect(try await f.me.fetchPendingUnlockRequests().first?.emailSentAt != nil)
        let unlock = try await f.me.redeemAccountabilityCode(requestID: request.id, code: FakeWorld.fixedAccountabilityCode)
        #expect(unlock.method == .accountabilityCode && unlock.requestID == request.id)
        await expectCode(.expired) { _ = try await f.me.redeemAccountabilityCode(requestID: request.id, code: FakeWorld.fixedAccountabilityCode) }
    }

    @Test func fiveWrongCodesLockTheRequest() async throws {
        let f = Fixture()
        f.world.setPushEnabled(false, for: FakeWorld.partnerID)
        let request = try await f.me.createUnlockRequest(minutes: 30, reason: nil)
        #expect(request.emailSentAt != nil) // notifications off: email goes out right away
        for _ in 0..<4 {
            await expectCode(.invalid) { _ = try await f.me.redeemAccountabilityCode(requestID: request.id, code: "000000") }
        }
        await expectCode(.tooManyAttempts) { _ = try await f.me.redeemAccountabilityCode(requestID: request.id, code: "000000") }
        await expectCode(.tooManyAttempts) { _ = try await f.me.redeemAccountabilityCode(requestID: request.id, code: FakeWorld.fixedAccountabilityCode) }
    }

    @Test func threeRequestsPerHour() async throws {
        let f = Fixture()
        for _ in 0..<3 { _ = try await f.me.createUnlockRequest(minutes: 15, reason: nil) }
        await expectCode(.rateLimited) { _ = try await f.me.createUnlockRequest(minutes: 15, reason: nil) }
        f.clock.advance(3601)
        _ = try await f.me.createUnlockRequest(minutes: 15, reason: nil)
        await expectCode(.invalid) { _ = try await f.me.createUnlockRequest(minutes: 20, reason: nil) }
        let solo = Fixture(paired: false)
        await expectCode(.partnerMissing) { _ = try await solo.me.createUnlockRequest(minutes: 15, reason: nil) }
    }

    @Test func spendingMinutes() async throws {
        let f = Fixture()
        let event = UUID()
        let unlock = try await f.me.spendMinutesUnlock(minutes: 15, clientEventID: event)
        #expect(unlock.method == .minutes && unlock.endsAt == f.clock.now.addingTimeInterval(900))
        #expect(try await f.me.fetchMinutes().mine.balance == 15)
        // Idempotent on the client event id.
        #expect(try await f.me.spendMinutesUnlock(minutes: 15, clientEventID: event) == unlock)
        #expect(try await f.me.fetchMinutes().mine.balance == 15)
        await expectCode(.insufficient) { _ = try await f.me.spendMinutesUnlock(minutes: 30, clientEventID: UUID()) }
        // The partner sees the new balance.
        #expect(try await f.ana.fetchMinutes().partner?.balance == 15)
    }

    @Test func dailyMaximumRefusal() async throws {
        let f = Fixture()
        f.world.seedGrant(120, to: FakeWorld.meID)
        _ = try await f.me.spendMinutesUnlock(minutes: 60, clientEventID: UUID())
        await expectCode(.overDailyMax) { _ = try await f.me.spendMinutesUnlock(minutes: 15, clientEventID: UUID()) }
        f.clock.set(at(2026, 11, 11, 0, 30))
        _ = try await f.me.spendMinutesUnlock(minutes: 15, clientEventID: UUID())
    }

    /// 07 §3 and device script 8: emergency with zero balance goes negative; second attempt the same week is refused.
    @Test func emergencyUnlock() async throws {
        let f = Fixture(paired: false)
        #expect(try await f.me.fetchMinutes().mine.balance == 0)
        #expect(try await f.me.lastEmergencyUnlock() == nil)
        let unlock = try await f.me.emergencyUnlock(clientEventID: UUID())
        #expect(unlock.minutes == 15 && unlock.method == .emergency)
        #expect(try await f.me.fetchMinutes().mine.balance == -15)
        #expect(try await f.me.lastEmergencyUnlock() == f.clock.now)
        await expectCode(.usedThisWeek) { _ = try await f.me.emergencyUnlock(clientEventID: UUID()) }
        await expectCode(.inDebt) { _ = try await f.me.spendMinutesUnlock(minutes: 15, clientEventID: UUID()) }
        f.clock.advance(7 * 86400)
        _ = try await f.me.emergencyUnlock(clientEventID: UUID())
        #expect(try await f.me.fetchMinutes().mine.balance == -30)
    }

    @Test func emergencyBreaksTheSharedStreakAndTellsThePartner() async throws {
        let f = Fixture()
        #expect(try await f.me.fetchStreak().currentLength == 4)
        var events = f.ana.events().makeAsyncIterator()
        _ = try await f.me.emergencyUnlock(clientEventID: UUID())
        #expect(await events.next() == .streakChanged(Streak(currentLength: 0, bestLength: 4)))
        #expect(await events.next() == .minutesChanged)
        #expect(await events.next() == .partnerStatusChanged)
        #expect(try await f.ana.fetchStreak().bestLength == 4)
    }

    /// 07 §3: offline QR sync is idempotent; a reused counter is rejected.
    @Test func qrSync() async throws {
        let f = Fixture()
        let event = QRUnlockEvent(counter: 59_000_001, minutes: 15, startedAt: f.clock.now.addingTimeInterval(-600))
        try await f.me.syncQRUnlocks([event])
        try await f.me.syncQRUnlocks([event])
        #expect(f.world.unlocks(of: FakeWorld.meID).count == 1)
        #expect(f.world.unlocks(of: FakeWorld.meID).first?.startedAt == event.startedAt)
        let reused = QRUnlockEvent(counter: 59_000_001, minutes: 30, startedAt: f.clock.now)
        await expectCode(.duplicateCounter) { try await f.ana.syncQRUnlocks([reused]) }
        // Free: no minutes spent.
        #expect(try await f.me.fetchMinutes().mine.balance == 30)
    }

    @Test func offlineFailsCleanly() async throws {
        let f = Fixture()
        f.me.setOffline(true)
        await expectCode(.offline) { _ = try await f.me.spendMinutesUnlock(minutes: 15, clientEventID: UUID()) }
        f.me.setOffline(false)
        _ = try await f.me.fetchMinutes()
    }
}

@Suite struct FakeMinutesAndChallengeTests {
    @Test func challengeCompletionAndConfirmation() async throws {
        let f = Fixture()
        let challenges = try await f.me.fetchChallenges()
        #expect(challenges.filter { $0.tier == .free }.count == 5)
        let note = try #require(challenges.first { $0.title == "Write your partner a note" })
        let completion = try await f.me.completeChallenge(id: note.id, note: "Left on the fridge")
        #expect(completion.expiresAt == f.clock.now.addingTimeInterval(48 * 3600))
        // Minutes are granted on confirmation, not before; only the partner can confirm.
        #expect(try await f.me.fetchMinutes().mine.balance == 30)
        await expectCode(.notPartner) { try await f.me.confirmCompletion(id: completion.id) }
        try await f.ana.confirmCompletion(id: completion.id)
        let minutes = try await f.me.fetchMinutes()
        #expect(minutes.mine.balance == 40 && minutes.partner?.balance == 30)
        await expectCode(.expired) { try await f.ana.confirmCompletion(id: completion.id) }
    }

    @Test func sharedChallengeGrantsBothOnOneConfirmation() async throws {
        let f = Fixture()
        let dinner = try #require(try await f.me.fetchChallenges().first { $0.title == "Phone-free dinner together" })
        let completion = try await f.ana.completeChallenge(id: dinner.id, note: nil)
        try await f.me.confirmCompletion(id: completion.id)
        let minutes = try await f.me.fetchMinutes()
        #expect(minutes.mine.balance == 50 && minutes.partner?.balance == 50)
    }

    @Test func unconfirmedCompletionsExpireAfter48Hours() async throws {
        let f = Fixture()
        let challenge = try #require(try await f.me.fetchChallenges().first { $0.tier == .free })
        let completion = try await f.me.completeChallenge(id: challenge.id, note: nil)
        f.clock.advance(48 * 3600)
        await expectCode(.expired) { try await f.ana.confirmCompletion(id: completion.id) }
        #expect(try await f.me.fetchCompletions().first?.status == .expired)
    }

    @Test func premiumGates() async throws {
        let f = Fixture()
        let library = try #require(try await f.me.fetchChallenges().first { $0.tier == .premium })
        await expectCode(.premiumRequired) { _ = try await f.me.completeChallenge(id: library.id, note: nil) }
        await expectCode(.premiumRequired) { _ = try await f.me.giveKudos(minutes: 10, message: "x", challengeID: nil) }
        await expectCode(.premiumRequired) {
            _ = try await f.me.createCustomChallenge(title: "x", description: "", minutes: 30, category: .together, isShared: true)
        }
    }

    @Test func kudosGrantCelebrateAndCap() async throws {
        let f = Fixture(premium: true)
        var events = f.ana.events().makeAsyncIterator()
        // One subscription covers both: the non-paying partner can give kudos too.
        _ = try await f.ana.giveKudos(minutes: 30, message: "Thanks for dinner", challengeID: nil)
        let kudos = try await f.me.giveKudos(minutes: 10, message: "You made me laugh today", challengeID: nil)
        #expect(await events.next() == .minutesChanged)
        #expect(await events.next() == .kudosReceived(kudos))
        #expect(try await f.ana.fetchMinutes().mine.balance == 40)
        #expect(try await f.me.fetchMinutes().mine.balance == 60)
        await expectCode(.invalid) { _ = try await f.me.giveKudos(minutes: 35, message: "", challengeID: nil) }
        await expectCode(.invalid) { _ = try await f.me.giveKudos(minutes: 3, message: "", challengeID: nil) }
        // 60 minutes of kudos per giver per day.
        _ = try await f.me.giveKudos(minutes: 30, message: "", challengeID: nil)
        _ = try await f.me.giveKudos(minutes: 20, message: "", challengeID: nil)
        await expectCode(.dailyCap) { _ = try await f.me.giveKudos(minutes: 5, message: "", challengeID: nil) }
        f.clock.set(at(2026, 11, 11, 8, 0))
        _ = try await f.me.giveKudos(minutes: 5, message: "", challengeID: nil)
        #expect(try await f.me.fetchKudos(limit: 10).count == 5)
    }

    @Test func customChallengeNeedsThePartnersApprovalOfTheValue() async throws {
        let f = Fixture(premium: true)
        let challenge = try await f.me.createCustomChallenge(title: "Fix the bike together", description: "", minutes: 30, category: .together, isShared: true)
        #expect(challenge.status == .pendingValueApproval)
        await expectCode(.invalid) { _ = try await f.me.completeChallenge(id: challenge.id, note: nil) }
        await expectCode(.notPartner) { _ = try await f.me.respondChallengeValue(challengeID: challenge.id, approve: true, counterMinutes: nil) }
        // The partner suggests a different value; now the creator approves it.
        let countered = try await f.ana.respondChallengeValue(challengeID: challenge.id, approve: false, counterMinutes: 20)
        #expect(countered.minutes == 20 && countered.status == .pendingValueApproval && countered.valueProposedBy == FakeWorld.partnerID)
        let active = try await f.me.respondChallengeValue(challengeID: challenge.id, approve: true, counterMinutes: nil)
        #expect(active.status == .active && active.minutes == 20)
        _ = try await f.me.completeChallenge(id: challenge.id, note: nil)
        await expectCode(.invalid) {
            _ = try await f.me.createCustomChallenge(title: "x", description: "", minutes: 90, category: .together, isShared: true)
        }
    }

    /// 07 §3: mutual reset requires both acceptances and expires everything first.
    @Test func mutualReset() async throws {
        let f = Fixture()
        f.world.seedGrant(40, to: FakeWorld.meID)
        _ = try await f.ana.emergencyUnlock(clientEventID: UUID())
        let proposal = try await f.me.proposeReset(standardMinutes: 30)
        #expect(try await f.ana.fetchResetProposals() == [proposal])
        // Nothing changes until the partner accepts; the proposer cannot accept their own proposal.
        #expect(try await f.me.fetchMinutes().mine.balance == 70)
        await expectCode(.notPartner) { try await f.me.respondReset(proposalID: proposal.id, accept: true) }
        try await f.ana.respondReset(proposalID: proposal.id, accept: true)
        let minutes = try await f.me.fetchMinutes()
        #expect(minutes.mine.balance == 30 && minutes.partner?.balance == 30 && minutes.partner?.debt == 0)
        #expect(minutes.mine.lots.count == 1)
        #expect(try await f.me.fetchResetProposals().isEmpty)
        let declined = try await f.me.proposeReset(standardMinutes: 30)
        try await f.ana.respondReset(proposalID: declined.id, accept: false)
        let expiring = try await f.me.proposeReset(standardMinutes: 30)
        f.clock.advance(24 * 3600)
        await expectCode(.expired) { try await f.ana.respondReset(proposalID: expiring.id, accept: true) }
    }

    @Test func minutesExpireAfterSevenDays() async throws {
        let f = Fixture()
        f.clock.advance(7 * 86400 - 1)
        #expect(try await f.me.fetchMinutes().mine.balance == 30)
        f.clock.advance(1)
        #expect(try await f.me.fetchMinutes().mine.balance == 0)
        #expect(try await f.me.fetchLedger(limit: 1).first?.type == .expire)
    }

    @Test func settingsValidation() async throws {
        let f = Fixture()
        var settings = try await f.me.fetchSettings()
        #expect(settings.dailyMaxMinutes == 60 && settings.startingMinutes == 30 && !settings.notificationPrefs.weeklyReportEmail)
        settings.dailyMaxMinutes = 120
        try await f.me.updateSettings(settings)
        #expect(try await f.me.fetchMinutes().mine.dailyMax == 120)
        settings.dailyMaxMinutes = 300
        await expectCode(.invalid) { try await f.me.updateSettings(settings) }
    }
}

@Suite struct FakeScheduleAndPremiumTests {
    /// 07 §3: stricter applies immediately; looser waits for approval; unpaired applies directly.
    @Test func stricterAppliesLooserWaits() async throws {
        let f = Fixture()
        var schedule = try #require(try await f.me.fetchSchedules().first)
        schedule.startLocal = LocalTime(hour: 17)
        #expect(try await f.me.submitScheduleChange(scheduleID: schedule.id, proposal: .schedule(schedule)) == .applied([schedule]))
        var looser = schedule
        looser.startLocal = LocalTime(hour: 19)
        guard case .pending(let request) = try await f.me.submitScheduleChange(scheduleID: schedule.id, proposal: .schedule(looser)) else {
            Issue.record("Looser change should wait")
            return
        }
        #expect(request.expiresAt == f.clock.now.addingTimeInterval(24 * 3600))
        #expect(try await f.me.fetchSchedules() == [schedule])
        #expect(try await f.ana.fetchScheduleChangeRequests() == [request])
        await expectCode(.notPartner) { try await f.me.respondScheduleChange(requestID: request.id, approve: true) }
        try await f.ana.respondScheduleChange(requestID: request.id, approve: true)
        #expect(try await f.me.fetchSchedules() == [looser])
    }

    @Test func letsTalkKeepsTheScheduleAndRequestsExpire() async throws {
        let f = Fixture()
        var schedule = try #require(try await f.me.fetchSchedules().first)
        let original = schedule
        schedule.enabled = false
        guard case .pending(let request) = try await f.me.submitScheduleChange(scheduleID: schedule.id, proposal: .schedule(schedule)) else {
            Issue.record("Turning protected time off should wait")
            return
        }
        try await f.ana.respondScheduleChange(requestID: request.id, approve: false)
        #expect(try await f.me.fetchSchedules() == [original])
        guard case .pending(let second) = try await f.me.submitScheduleChange(scheduleID: nil, proposal: .fewerPausedApps) else {
            Issue.record("Fewer paused apps should wait")
            return
        }
        f.clock.advance(24 * 3600)
        await expectCode(.expired) { try await f.ana.respondScheduleChange(requestID: second.id, approve: true) }
    }

    @Test func unpairedChangesApplyDirectly() async throws {
        let f = Fixture(paired: false)
        var schedule = try #require(try await f.me.fetchSchedules().first)
        schedule.enabled = false
        #expect(try await f.me.submitScheduleChange(scheduleID: schedule.id, proposal: .schedule(schedule)) == .applied([schedule]))
        #expect(try await f.me.submitScheduleChange(scheduleID: nil, proposal: .fewerPausedApps) == .applied([schedule]))
    }

    @Test func extraSchedulesArePremium() async throws {
        let f = Fixture()
        let lunch = ProtectedSchedule(name: "Lunch", startLocal: LocalTime(hour: 12), endLocal: LocalTime(hour: 13))
        await expectCode(.premiumRequired) { _ = try await f.me.submitScheduleChange(scheduleID: nil, proposal: .schedule(lunch)) }
        f.world.setEntitlement(.subscription, for: FakeWorld.partnerID)
        guard case .applied(let schedules) = try await f.me.submitScheduleChange(scheduleID: nil, proposal: .schedule(lunch)) else {
            Issue.record("Adding a schedule is stricter")
            return
        }
        #expect(schedules.count == 2)
        guard case .pending = try await f.me.submitScheduleChange(scheduleID: lunch.id, proposal: .removeSchedule) else {
            Issue.record("Removing a schedule is looser")
            return
        }
    }

    /// 07 §3: pair premium when the payer is active; non-payer loses premium on unpair; trial counted once per pair.
    @Test func pairPremium() async throws {
        let f = Fixture()
        #expect(try await f.me.fetchPremium() == .free)
        var events = f.ana.events().makeAsyncIterator()
        f.world.setEntitlement(.trial, for: FakeWorld.meID, expiresAt: f.clock.now.addingTimeInterval(14 * 86400))
        #expect(await events.next() == .premiumChanged)
        let partnerView = try await f.ana.fetchPremium()
        #expect(partnerView.isPremium && partnerView.payerID == FakeWorld.meID && partnerView.kind == .trial && partnerView.trialUsed)
        // Trial ends without a purchase: graceful downgrade.
        f.clock.advance(14 * 86400)
        #expect(!(try await f.ana.fetchPremium()).isPremium)
        #expect(try await f.ana.fetchPremium().trialUsed)
        f.world.setEntitlement(.lifetime, for: FakeWorld.meID)
        #expect(try await f.ana.fetchPremium().isPremium)
        try await f.me.unpair()
        #expect(try await f.me.fetchPremium().isPremium)
        #expect(!(try await f.ana.fetchPremium()).isPremium)
    }

    @Test func partnerStatusAndProfile() async throws {
        let f = Fixture()
        var events = f.ana.events().makeAsyncIterator()
        try await f.me.setProtectedTimeOff(true)
        #expect(await events.next() == .streakChanged(Streak(currentLength: 0, bestLength: 4)))
        #expect(await events.next() == .partnerStatusChanged)
        #expect(try await f.ana.fetchPairState()?.partner.protectedTimeOffSince == f.clock.now)
        try await f.me.setProtectedTimeOff(false)
        #expect(try await f.ana.fetchPairState()?.partner.protectedTimeOffSince == nil)
        #expect(try await f.me.updateProfile(displayName: "Rafael", timeZone: nil).displayName == "Rafael")
        #expect(try await f.ana.fetchPairState()?.partner.displayName == "Rafael")
    }

    @Test func weeklyReportAndActivity() async throws {
        let f = Fixture(premium: true)
        let challenge = try #require(try await f.me.fetchChallenges().first { $0.isShared })
        let completion = try await f.me.completeChallenge(id: challenge.id, note: nil)
        try await f.ana.confirmCompletion(id: completion.id)
        _ = try await f.me.giveKudos(minutes: 10, message: "Thanks", challengeID: nil)
        let request = try await f.me.createUnlockRequest(minutes: 30, reason: nil)
        try await f.ana.respondUnlockRequest(id: request.id, approve: true)
        _ = try await f.me.spendMinutesUnlock(minutes: 15, clientEventID: UUID())
        let report = try #require(try await f.me.fetchWeeklyReports().first)
        let mine = report.stats(for: FakeWorld.meID), theirs = report.stats(for: FakeWorld.partnerID)
        #expect(mine.minutesEarned == 20 && mine.minutesSpent == 15 && mine.challengesCompleted == 1)
        #expect(mine.requestsSent == 1 && mine.requestsApproved == 1 && mine.kudosGiven == 1 && mine.kudosReceived == 0)
        #expect(theirs.minutesEarned == 30 && theirs.kudosReceived == 1)
        #expect(report.totalEarnedTogether == 50 && report.sharedChallengesDone == 1 && report.streak == 4)
        #expect(report.mostGenerousUserID == FakeWorld.meID)
        #expect(report.weekStart == LocalDay(year: 2026, month: 11, day: 9))
        let feed = try await f.ana.fetchActivity(limit: 20)
        #expect(feed.first?.kind == .unlock)
        #expect(Set(feed.map(\.kind)).isSuperset(of: [.kudos, .challengeConfirmed, .requestApproved, .paired]))
    }

    @Test func exportAndDeleteAccount() async throws {
        let f = Fixture()
        let data = try await f.me.exportMyData()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["email"] as? String == "rafa@example.com")
        #expect(json["ledger"] != nil && json["schedules"] != nil)
        try await f.me.deleteAccount()
        // Deletes the account and unpairs the partner.
        #expect(await f.me.currentSession() == nil)
        #expect(f.world.deletedUsers == [FakeWorld.meID])
        #expect(!f.world.hasPerson(FakeWorld.meID))
        #expect(try await f.ana.fetchPairState() == nil)
    }
}

@Suite struct PartnerBotTests {
    @Test func botAcceptsInviteAndApprovesRequests() async throws {
        let world = FakeWorld()
        world.addPerson(id: FakeWorld.partnerID, name: "Ana", email: "ana@example.com")
        let me = FakeBackend(world: world)
        _ = try await me.signInWithApple(idToken: "", nonce: nil, fullName: nil)
        var behavior = FakePartnerBot.Behavior()
        behavior.delay = .milliseconds(20)
        behavior.inviteDelay = .milliseconds(20)
        let bot = FakePartnerBot(backend: FakeBackend(world: world, signedInAs: FakeWorld.partnerID), userBackend: me, behavior: behavior)
        let task = bot.start()
        defer { task.cancel() }
        var events = me.events().makeAsyncIterator()
        _ = try await me.createInvite()
        #expect(await events.next() == .pairChanged)
        #expect(try await me.fetchPairState()?.partner.displayName == "Ana")
        _ = await events.next() // minutesChanged from the starting grants
        let request = try await me.createUnlockRequest(minutes: 30, reason: nil)
        guard case .unlockRequestChanged(let updated, let unlock)? = await events.next() else {
            Issue.record("The bot did not answer")
            return
        }
        #expect(updated.id == request.id && updated.status == .approved && unlock != nil)
    }

    @Test func botActions() async throws {
        let f = Fixture(premium: true)
        let bot = FakePartnerBot(backend: f.ana, userBackend: f.me)
        await bot.perform(.sendKudos)
        #expect(try await f.me.fetchMinutes().mine.balance == 40)
        await bot.perform(.askUnlock)
        #expect(try await f.me.fetchPendingUnlockRequests().first?.reason == "Reply to a client")
        await bot.perform(.proposeReset)
        #expect(try await f.me.fetchResetProposals().count == 1)
        await bot.perform(.proposeScheduleChange)
        #expect(try await f.me.fetchScheduleChangeRequests().count == 1)
        await bot.perform(.completeChallenge)
        #expect(try await f.me.fetchCompletions().first?.completedBy == FakeWorld.partnerID)
        await bot.perform(.proposeCustomChallenge)
        #expect(try await f.me.fetchChallenges().contains { $0.status == .pendingValueApproval })
    }
}

@Suite struct BackendJSONTests {
    @Test func keyConversion() {
        #expect(BackendJSON.camelCase("pair_id") == "pairID")
        #expect(BackendJSON.camelCase("client_event_id") == "clientEventID")
        #expect(BackendJSON.camelCase("expires_at") == "expiresAt")
        #expect(BackendJSON.camelCase("id") == "id")
        #expect(BackendJSON.snakeCase("pairID") == "pair_id")
        #expect(BackendJSON.snakeCase("clientEventID") == "client_event_id")
        #expect(BackendJSON.snakeCase("startLocal") == "start_local")
    }

    @Test func decodesDatabaseRows() throws {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","pair_id":"22222222-2222-2222-2222-222222222222",
          "requester_id":"33333333-3333-3333-3333-333333333333","minutes":30,"reason":null,"status":"pending",
          "expires_at":"2026-11-14T01:05:00.123456+00:00","code_hash":null,"code_attempts":0,"email_sent_at":null,
          "created_at":"2026-11-14T01:00:00+00:00"}]
        """
        let requests = try BackendJSON.decoder.decode([UnlockRequest].self, from: Data(json.utf8))
        #expect(requests.first?.minutes == 30 && requests.first?.status == .pending)
        #expect(requests.first.map { $0.expiresAt.timeIntervalSince($0.createdAt) > 300 } == true)
        let schedule = """
        {"id":"11111111-1111-1111-1111-111111111111","user_id":"33333333-3333-3333-3333-333333333333","name":"",
         "weekdays":[1,2,3,4,5,6,7],"start_local":"18:00:00","end_local":"09:00:00","enabled":true}
        """
        #expect(try BackendJSON.decoder.decode(ProtectedSchedule.self, from: Data(schedule.utf8)).endLocal == LocalTime(hour: 9))
        let settings = #"{"user_id":"x","daily_max_minutes":90,"starting_minutes":30,"notification_prefs":{"weekly_report_email":true,"muted":["kudos"]}}"#
        let decoded = try BackendJSON.decoder.decode(UserSettings.self, from: Data(settings.utf8))
        #expect(decoded.dailyMaxMinutes == 90 && decoded.notificationPrefs.weeklyReportEmail && decoded.notificationPrefs.isMuted(.kudos))
    }

    @Test func encodesFunctionBodiesInSnakeCase() throws {
        var schedule = ProtectedSchedule.standard()
        schedule.weekdays = [1]
        guard case .object(let object) = JSONValue.from(ScheduleProposal.schedule(schedule)),
              case .object(let inner)? = object["schedule"] else {
            Issue.record("Unexpected shape")
            return
        }
        #expect(object["kind"] == .string("schedule"))
        #expect(inner["start_local"] == .string("18:00:00") && inner["weekdays"] == .array([.int(1)]) && inner["enabled"] == .bool(true))
        let events = JSONValue.from([QRUnlockEvent(counter: 5, minutes: 15, startedAt: Date(timeIntervalSince1970: 0))])
        guard case .array(let list) = events, case .object(let event)? = list.first else {
            Issue.record("Unexpected shape")
            return
        }
        #expect(event["counter"] == .int(5) && event["client_event_id"] != nil && event["started_at"] == .string("1970-01-01T00:00:00Z"))
    }

    @Test func envelope() throws {
        struct Payload: Decodable, Equatable { var code: String }
        let ok = Data(#"{"ok":true,"data":{"code":"ABC123"}}"#.utf8)
        #expect(try FunctionEnvelope<Payload>.unwrap(ok) == Payload(code: "ABC123"))
        let failure = Data(#"{"ok":false,"error":{"code":"over_daily_max","message":"Daily maximum reached"}}"#.utf8)
        #expect(throws: BackendError(.overDailyMax, message: "Daily maximum reached")) { try FunctionEnvelope<Payload>.unwrap(failure) }
        _ = try FunctionEnvelope<Empty>.unwrap(Data(#"{"ok":true}"#.utf8))
        #expect(throws: BackendError.self) { try FunctionEnvelope<Payload>.unwrap(Data("oops".utf8)) }
    }

    @Test func secretsAndRealtimeMapping() {
        #expect(BackendJSON.secretData("00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff") == Data([UInt8](repeating: 0, count: 20).enumerated().map { $0.offset % 2 == 0 ? 0 : 255 }))
        #expect(BackendJSON.secretData(Data(repeating: 7, count: 20).base64EncodedString()) == Data(repeating: 7, count: 20))
        #expect(SupabaseBackend.event(forTable: "minute_lots") == .minutesChanged)
        #expect(SupabaseBackend.event(forTable: "pair_coverage") == .premiumChanged)
        #expect(SupabaseBackend.event(forTable: "unlock_requests") == nil)
    }
}
