import Foundation
import Testing
@testable import Core

@Suite struct MinutesLedgerTests {
    let user = UUID()
    let calendar = Calendar.gregorian(in: newYork)
    let t0 = local(2026, 11, 10, 12, 0)

    func ledger() -> MinutesLedger { MinutesLedger(userID: user) }

    /// 07 §3: earned lots expire exactly 7 days later.
    @Test func lotsExpireExactlySevenDaysLater() {
        var l = ledger()
        l.grant(20, type: .earnChallenge, now: t0, calendar: calendar)
        #expect(l.openLots.first?.expiresAt == t0.addingTimeInterval(7 * 86400))
        l.expire(now: t0.addingTimeInterval(7 * 86400 - 1), calendar: calendar)
        #expect(l.balance == 20)
        l.expire(now: t0.addingTimeInterval(7 * 86400), calendar: calendar)
        #expect(l.balance == 0)
        #expect(l.entries.last?.type == .expire && l.entries.last?.minutes == -20)
    }

    /// 07 §3: spent minutes come from the soonest-expiring lot; spending across two lots splits correctly.
    @Test func spendingIsFIFOByExpiryAndSplitsAcrossLots() throws {
        var l = ledger()
        l.grant(20, type: .earnChallenge, now: t0, calendar: calendar)
        l.grant(30, type: .earnKudos, now: t0.addingTimeInterval(86400), calendar: calendar)
        let now = t0.addingTimeInterval(2 * 86400)
        try l.spend(30, dailyMax: 60, now: now, calendar: calendar)
        #expect(l.openLots.count == 1)
        #expect(l.openLots[0].remaining == 20 && l.openLots[0].granted == 30)
        let spends = l.entries.filter { $0.type == .spendUnlock }
        #expect(spends.map(\.minutes) == [-20, -10])
        #expect(l.balance == 20)
    }

    @Test func insufficientBalanceIsRefused() {
        var l = ledger()
        l.grant(10, type: .startingGrant, now: t0, calendar: calendar)
        #expect(throws: MinutesError.insufficient) { try l.spend(15, dailyMax: 60, now: t0, calendar: calendar) }
        #expect(l.balance == 10)
    }

    /// 07 §3: the daily maximum uses the user's local day (11:30 PM and 12:30 AM in UTC−5).
    @Test func dailyMaximumUsesTheLocalDay() throws {
        var l = ledger()
        l.grant(60, type: .earnChallenge, now: t0, calendar: calendar)
        l.grant(60, type: .earnChallenge, now: t0, calendar: calendar)
        let lateEvening = local(2026, 11, 10, 23, 30)
        try l.spend(45, dailyMax: 60, now: lateEvening, calendar: calendar)
        #expect(throws: MinutesError.overDailyMax) { try l.spend(30, dailyMax: 60, now: lateEvening, calendar: calendar) }
        // One hour later it is a new local day (though the same UTC day), so the spend is allowed.
        let afterMidnight = local(2026, 11, 11, 0, 30)
        try l.spend(30, dailyMax: 60, now: afterMidnight, calendar: calendar)
        #expect(l.spentToday(now: afterMidnight, calendar: calendar) == 30)
        #expect(l.spentToday(now: lateEvening, calendar: calendar) == 45)
        #expect(l.balance == 45)
    }

    /// 07 §3: debt from an emergency unlock is repaid before new lots; spending is refused while in debt.
    @Test func debtIsRepaidFirstAndBlocksSpending() throws {
        var l = ledger()
        l.borrow(15, now: t0, calendar: calendar)
        #expect(l.balance == -15 && l.debt == 15)
        #expect(throws: MinutesError.inDebt) { try l.spend(15, dailyMax: 60, now: t0, calendar: calendar) }
        l.grant(10, type: .earnChallenge, now: t0, calendar: calendar)
        #expect(l.debt == 5 && l.openLots.isEmpty && l.balance == -5)
        l.grant(20, type: .earnKudos, now: t0, calendar: calendar)
        #expect(l.debt == 0 && l.balance == 15)
        #expect(l.entries.filter { $0.type == .debtRepay }.map(\.minutes) == [10, 5])
        try l.spend(15, dailyMax: 60, now: t0, calendar: calendar)
        #expect(l.balance == 0)
    }

    /// Matches the server's borrow_minutes: minutes in hand are used first; only a shortfall is debt.
    @Test func borrowingUsesTheBalanceFirstAndOnlyTheShortfallIsDebt() throws {
        var l = ledger()
        l.grant(40, type: .earnChallenge, now: t0, calendar: calendar)
        l.borrow(15, now: t0, calendar: calendar)
        #expect(l.balance == 25 && l.debt == 0)
        try l.spend(15, dailyMax: 60, now: t0, calendar: calendar)
        // The borrow does not count toward the daily maximum; only the spend does.
        #expect(l.spentToday(now: t0, calendar: calendar) == 15)
        l.borrow(15, now: t0, calendar: calendar)
        #expect(l.balance == -5 && l.debt == 5)
        #expect(throws: MinutesError.inDebt) { try l.spend(15, dailyMax: 60, now: t0, calendar: calendar) }
    }

    /// P26: ending a minutes unlock early gives back the unused whole minutes to their lots.
    @Test func refundGoesBackToTheLotsWithTheirExpiry() throws {
        var l = ledger()
        l.grant(10, type: .earnKudos, now: t0, calendar: calendar)
        l.grant(50, type: .earnKudos, now: t0.addingTimeInterval(86400), calendar: calendar)
        let unlock = UUID()
        try l.spend(30, dailyMax: 60, unlockID: unlock, now: t0.addingTimeInterval(2 * 86400), calendar: calendar)
        #expect(l.balance == 30)
        let back = l.refund(20, unlockID: unlock, now: t0.addingTimeInterval(2 * 86400 + 600), calendar: calendar)
        #expect(back == 20 && l.balance == 50)
        // The latest-expiring lot got the minutes back, with its original expiry.
        #expect(l.openLots.last?.remaining == 50 && l.openLots.last?.expiresAt == t0.addingTimeInterval(8 * 86400))
        #expect(l.spentToday(now: t0.addingTimeInterval(2 * 86400 + 600), calendar: calendar) == 10)
    }

    /// 07 §3: reset expires everything (lots and debt) first, then grants the standard amount.
    @Test func resetExpiresEverythingFirst() {
        var l = ledger()
        l.grant(50, type: .earnChallenge, now: t0, calendar: calendar)
        l.borrow(15, now: t0, calendar: calendar)
        l.reset(to: 30, now: t0.addingTimeInterval(60), calendar: calendar)
        #expect(l.balance == 30 && l.debt == 0)
        #expect(l.openLots.count == 1)
        #expect(l.openLots[0].expiresAt == t0.addingTimeInterval(60 + 7 * 86400))
        #expect(l.entries.suffix(2).map(\.type) == [.expire, .reset])
        // Unpair: reset to zero keeps the history but leaves nothing active.
        l.reset(to: 0, now: t0.addingTimeInterval(120), calendar: calendar)
        #expect(l.balance == 0 && l.openLots.isEmpty)
        #expect(!l.entries.isEmpty)
    }

    @Test func expiredMinutesCannotBeSpent() {
        var l = ledger()
        l.grant(30, type: .startingGrant, now: t0, calendar: calendar)
        let later = t0.addingTimeInterval(8 * 86400)
        #expect(throws: MinutesError.insufficient) { try l.spend(15, dailyMax: 60, now: later, calendar: calendar) }
    }

    @Test func summaryReflectsLedger() throws {
        var l = ledger()
        l.grant(45, type: .earnChallenge, now: t0, calendar: calendar)
        try l.spend(15, dailyMax: 60, now: t0, calendar: calendar)
        let s = l.summary(now: t0, calendar: calendar, dailyMax: 60)
        #expect(s.balance == 30 && s.spentToday == 15 && s.remainingToday == 45 && s.available == 30)
        var inDebt = MinutesSummary(userID: user, lots: s.lots, debt: 40)
        #expect(inDebt.balance == -10 && inDebt.available == 0)
        inDebt.debt = 0
        #expect(inDebt.available == 30)
    }
}

@Suite struct ExpiryTimelineTests {
    let calendar = Calendar.gregorian(in: newYork)
    let user = UUID()

    func lot(_ minutes: Int, expires: Date) -> MinuteLot {
        MinuteLot(userID: user, granted: minutes, remaining: minutes, expiresAt: expires, createdAt: expires.addingTimeInterval(-7 * 86400))
    }

    @Test func bucketsByLocalDay() {
        let now = local(2026, 11, 10, 20) // Tuesday evening
        let lots = [
            lot(12, expires: local(2026, 11, 12, 9)), // Thursday
            lot(20, expires: local(2026, 11, 14, 23, 59)), // Saturday
            lot(5, expires: local(2026, 11, 14, 1)),
            lot(8, expires: local(2026, 11, 17, 19)), // exactly a week out
        ]
        let buckets = ExpiryTimeline.buckets(lots: lots, now: now, calendar: calendar)
        #expect(buckets.count == 7)
        #expect(buckets.first?.day == LocalDay(year: 2026, month: 11, day: 11))
        #expect(buckets.map(\.minutes) == [0, 12, 0, 25, 0, 0, 8])
    }

    @Test func todayIsShownWhenSomethingExpiresToday() {
        let now = local(2026, 11, 10, 8)
        let buckets = ExpiryTimeline.buckets(lots: [lot(10, expires: local(2026, 11, 10, 22))], now: now, calendar: calendar)
        #expect(buckets.count == 7)
        #expect(buckets.first?.minutes == 10)
        #expect(buckets.first?.day == LocalDay(year: 2026, month: 11, day: 10))
    }

    @Test func expiredAndEmptyLotsAreIgnored() {
        let now = local(2026, 11, 10, 8)
        var spent = lot(10, expires: local(2026, 11, 12, 8))
        spent.remaining = 0
        let buckets = ExpiryTimeline.buckets(lots: [spent, lot(9, expires: local(2026, 11, 10, 7))], now: now, calendar: calendar)
        #expect(buckets.allSatisfy { $0.minutes == 0 })
    }

    @Test func expiringTomorrow() {
        let now = local(2026, 11, 10, 19)
        let lots = [lot(15, expires: local(2026, 11, 11, 0, 5)), lot(7, expires: local(2026, 11, 11, 23)), lot(9, expires: local(2026, 11, 12, 0, 1))]
        #expect(ExpiryTimeline.expiringTomorrow(lots: lots, now: now, calendar: calendar) == 22)
    }
}

@Suite struct UnlockRulesTests {
    @Test func lengths() {
        #expect(UnlockRules.allowedLengths(isPremium: false) == [15, 30, 60])
        #expect(UnlockRules.defaultLength == 30)
        let premium = UnlockRules.allowedLengths(isPremium: true)
        #expect(premium.first == 15 && premium.contains(45) && premium.contains(90))
        #expect(premium.allSatisfy { $0 % 15 == 0 })
        #expect(!UnlockRules.isValidLength(45, isPremium: false))
        #expect(UnlockRules.isValidLength(45, isPremium: true))
        #expect(!UnlockRules.isValidLength(10, isPremium: true))
    }

    /// P14, P26: use is counted in whole minutes, rounded up; refunds count whole unused minutes.
    @Test func minutesAreCountedRoundedUp() {
        let start = local(2026, 11, 10, 20, 0)
        #expect(UnlockRules.minutesUsed(from: start, to: start.addingTimeInterval(2)) == 1)
        #expect(UnlockRules.minutesUsed(from: start, to: start.addingTimeInterval(120)) == 2)
        #expect(UnlockRules.minutesUsed(from: start, to: start.addingTimeInterval(121)) == 3)
        #expect(UnlockRules.unusedWholeMinutes(endsAt: start.addingTimeInterval(30 * 60), now: start.addingTimeInterval(570)) == 20)
    }

    /// P14: a weekly allowance across sessions, from the first use; changes apply right away.
    @Test func emergencyAllowanceAcrossSessions() {
        let user = UUID()
        let first = local(2026, 11, 10, 20, 0)
        func session(_ start: Date, minutes: Int, used: Int?) -> Unlock {
            Unlock(id: UUID(), userID: user, method: .emergency, minutes: minutes, startedAt: start,
                   endsAt: start.addingTimeInterval(Double(used ?? minutes) * 60), minutesUsed: used)
        }
        #expect(EmergencyRules.status(allowance: 15, sessions: [], now: first).remaining == 15)
        let ended = session(first, minutes: 15, used: 2)
        let status = EmergencyRules.status(allowance: 15, sessions: [ended], now: first.addingTimeInterval(600))
        #expect(status.used == 2 && status.remaining == 13)
        #expect(status.renewsAt == first.addingTimeInterval(7 * 86400))
        // A running session reserves what it may still use.
        let running = session(first.addingTimeInterval(86400), minutes: 13, used: nil)
        #expect(EmergencyRules.status(allowance: 15, sessions: [ended, running], now: first.addingTimeInterval(86400 + 60)).isUsedUp)
        // Raising the allowance mid-week; lowering it never goes below zero.
        #expect(EmergencyRules.status(allowance: 30, sessions: [ended], now: first.addingTimeInterval(600)).remaining == 28)
        #expect(EmergencyRules.status(allowance: 15, sessions: [ended, running], now: first.addingTimeInterval(86400 + 60)).remaining == 0)
        // After 7 days the window closes; the next use opens a new one.
        #expect(EmergencyRules.status(allowance: 15, sessions: [ended, running], now: first.addingTimeInterval(7 * 86400)).remaining == 15)
        let later = session(first.addingTimeInterval(8 * 86400), minutes: 15, used: 5)
        let next = EmergencyRules.status(allowance: 15, sessions: [ended, running, later], now: first.addingTimeInterval(8 * 86400 + 600))
        #expect(next.used == 5 && next.renewsAt == first.addingTimeInterval(15 * 86400))
    }

    @Test func unlockingAgainExtendsTheWindow() {
        let now = local(2026, 11, 10, 20)
        let first = ActiveUnlock.starting(id: UUID(), minutes: 30, now: now, current: nil)
        #expect(first.endsAt == now.addingTimeInterval(1800))
        let second = ActiveUnlock.starting(id: UUID(), minutes: 15, now: now.addingTimeInterval(600), current: first)
        #expect(second.startedAt == now && second.endsAt == now.addingTimeInterval(2700))
        // A finished window does not extend.
        let third = ActiveUnlock.starting(id: UUID(), minutes: 15, now: now.addingTimeInterval(4000), current: second)
        #expect(third.startedAt == now.addingTimeInterval(4000))
        #expect(first.isActive(at: now) && !first.isActive(at: first.endsAt))
    }
}

@Suite struct UnlockRequestFlowTests {
    let now = local(2026, 11, 10, 20)

    func request(_ status: UnlockRequestStatus = .pending, id: UUID = UUID()) -> UnlockRequest {
        UnlockRequest(id: id, pairID: UUID(), requesterID: UUID(), minutes: 30, status: status, expiresAt: now.addingTimeInterval(300), createdAt: now)
    }

    func unlock(for r: UnlockRequest) -> Unlock {
        Unlock(id: UUID(), userID: r.requesterID, method: .partnerApproval, minutes: r.minutes, startedAt: now, endsAt: now.addingTimeInterval(1800), requestID: r.id)
    }

    @Test func approval() {
        let r = request()
        var flow = UnlockRequestFlow.idle.reduce(.created(r))
        #expect(flow == .waiting(r))
        var approved = r
        approved.status = .approved
        let u = unlock(for: r)
        flow = flow.reduce(.updated(approved, unlock: u))
        #expect(flow == .approved(u) && flow.isTerminal)
    }

    @Test func letsWait() {
        let r = request()
        var declined = r
        declined.status = .declined
        let flow = UnlockRequestFlow.waiting(r).reduce(.updated(declined, unlock: nil))
        #expect(flow == .declined(declined))
    }

    /// 07 §3: request expires at 5 minutes; approval after expiry fails.
    @Test func expiresAtFiveMinutesAndLateApprovalIsIgnored() {
        let r = request()
        var flow = UnlockRequestFlow.waiting(r)
        flow = flow.reduce(.tick(now.addingTimeInterval(299)))
        #expect(flow == .waiting(r))
        flow = flow.reduce(.tick(now.addingTimeInterval(300)))
        #expect(flow == .expired(r))
        var approved = r
        approved.status = .approved
        #expect(flow.reduce(.updated(approved, unlock: unlock(for: r))) == .expired(r))
        #expect(flow.reduce(.codeRedeemed(unlock(for: r))) == .expired(r))
        #expect(flow.reduce(.reset) == .idle)
    }

    @Test func updatesForOtherRequestsAreIgnored() {
        let r = request()
        var other = request(.approved)
        other.status = .approved
        #expect(UnlockRequestFlow.waiting(r).reduce(.updated(other, unlock: unlock(for: other))) == .waiting(r))
    }

    @Test func approvalWithoutAnUnlockKeepsWaiting() {
        let r = request()
        var approved = r
        approved.status = .approved
        #expect(UnlockRequestFlow.waiting(r).reduce(.updated(approved, unlock: nil)) == .waiting(r))
    }

    @Test func codeRedeemAndCancel() {
        let r = request()
        let u = unlock(for: r)
        #expect(UnlockRequestFlow.waiting(r).reduce(.codeRedeemed(u)) == .approved(u))
        #expect(UnlockRequestFlow.waiting(r).reduce(.cancel) == .cancelled)
        #expect(UnlockRequestFlow.idle.reduce(.cancel) == .idle)
        #expect(UnlockRequestFlow.idle.reduce(.created(request(.expired))) == .idle)
    }

    @Test func codeEntryAppearsAfterTwoMinutesOrWhenEmailWasSent() {
        var r = request()
        #expect(!UnlockRequestFlow.waiting(r).codeEntryAvailable(now: now.addingTimeInterval(60)))
        #expect(UnlockRequestFlow.waiting(r).codeEntryAvailable(now: now.addingTimeInterval(120)))
        r.emailSentAt = now.addingTimeInterval(5)
        #expect(UnlockRequestFlow.waiting(r).codeEntryAvailable(now: now.addingTimeInterval(10)))
        #expect(!UnlockRequestFlow.idle.codeEntryAvailable(now: now))
    }
}

@Suite struct SharedStateAndLinksTests {
    @Test func phases() {
        var state = SharedState()
        state.schedules = [.standard()]
        let night = local(2026, 11, 10, 22)
        #expect(state.phase(at: night, timeZone: newYork) == .protected(until: local(2026, 11, 11, 9)))
        #expect(state.phase(at: local(2026, 11, 10, 12), timeZone: newYork) == .open(next: local(2026, 11, 10, 18)))
        state.activeUnlock = ActiveUnlock(id: UUID(), startedAt: night, endsAt: night.addingTimeInterval(1800))
        #expect(state.phase(at: night.addingTimeInterval(60), timeZone: newYork) == .unlocked(until: night.addingTimeInterval(1800)))
        #expect(state.phase(at: night.addingTimeInterval(1800), timeZone: newYork) == .protected(until: local(2026, 11, 11, 9)))
        // An unlock that outlives protected time is capped at its end.
        let morning = local(2026, 11, 11, 8, 50)
        state.activeUnlock = ActiveUnlock(id: UUID(), startedAt: morning, endsAt: morning.addingTimeInterval(1800))
        #expect(state.phase(at: morning, timeZone: newYork) == .unlocked(until: local(2026, 11, 11, 9)))
    }

    @Test func phaseChangesForWidgetTimelines() {
        var state = SharedState()
        state.schedules = [.standard()]
        let night = local(2026, 11, 10, 22)
        state.activeUnlock = ActiveUnlock(id: UUID(), startedAt: night, endsAt: night.addingTimeInterval(1800))
        let changes = state.phaseChanges(after: night, timeZone: newYork, limit: 4)
        #expect(changes == [night.addingTimeInterval(1800), local(2026, 11, 11, 9), local(2026, 11, 11, 18), local(2026, 11, 12, 9)])
        #expect(SharedState().phaseChanges(after: night, timeZone: newYork).isEmpty)
    }

    @Test func pushIntents() {
        let id = UUID()
        func parse(_ category: String, _ action: String?, _ payload: [String: String]) -> PushIntent? {
            PushIntent.parse(category: category, action: action, payload: payload, urlScheme: "couplesapp")
        }
        #expect(parse("UNLOCK_REQUEST", "GO_FOR_IT", ["request_id": id.uuidString]) == .answerUnlockRequest(id: id, approve: true))
        #expect(parse("UNLOCK_REQUEST", "LETS_WAIT", ["request_id": id.uuidString]) == .answerUnlockRequest(id: id, approve: false))
        #expect(parse("COMPLETION_CONFIRM", "CONFIRM", ["completion_id": id.uuidString]) == .confirmCompletion(id: id))
        #expect(parse("SCHEDULE_CHANGE", "APPROVE", ["change_id": id.uuidString]) == .answerScheduleChange(id: id, approve: true))
        #expect(parse("SCHEDULE_CHANGE", "LETS_TALK", ["change_id": id.uuidString]) == .answerScheduleChange(id: id, approve: false))
        // Tapping the notification itself opens the matching place.
        #expect(parse("UNLOCK_REQUEST", nil, ["request_id": id.uuidString]) == .open(URL(string: "couplesapp://request/\(id.uuidString)")!))
        #expect(parse("", nil, ["link": "couplesapp://unlock"]) == .open(URL(string: "couplesapp://unlock")!))
        #expect(parse("", nil, ["kind": "weekly_report"]) == .open(URL(string: "couplesapp://weekly_report")!))
        #expect(parse("", nil, ["challenge_id": id.uuidString]) == .open(URL(string: "couplesapp://challenge/\(id.uuidString)")!))
        // A button without its id does nothing rather than guessing.
        #expect(parse("UNLOCK_REQUEST", "GO_FOR_IT", [:]) == nil)
        #expect(DeepLink.parse(URL(string: "couplesapp://weekly_report")!, scheme: "couplesapp", domain: "example.com") == .weeklyReport)
        #expect(DeepLink.parse(URL(string: "couplesapp://minutes_expiring")!, scheme: "couplesapp", domain: "example.com") == .minutes)
        #expect(DeepLink.parse(URL(string: "couplesapp://schedule_request")!, scheme: "couplesapp", domain: "example.com") == .schedule)
    }

    @Test func storeRoundTripsAndToleratesOldData() throws {
        let store = InMemoryStateStore()
        store.update { $0.partnerName = "Ana"; $0.myBalance = 45 }
        #expect(store.load().partnerName == "Ana")
        store.saveSelectionData(Data([1, 2, 3]))
        #expect(store.loadSelectionData() == Data([1, 2, 3]))
        let decoded = try JSONDecoder().decode(SharedState.self, from: Data("{}".utf8))
        #expect(decoded == SharedState())

        let suite = "test.\(UUID().uuidString)"
        let group = AppGroupStateStore(suiteName: suite)
        group.update { $0.streak = 7; $0.schedules = [.standard()] }
        #expect(AppGroupStateStore(suiteName: suite).load().streak == 7)
        group.reset()
        #expect(group.load() == SharedState())
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func deepLinks() {
        let id = UUID()
        func parse(_ s: String) -> DeepLink? { DeepLink.parse(URL(string: s)!, scheme: "couplesapp", domain: "example.com") }
        #expect(parse("couplesapp://unlock") == .unlock)
        #expect(parse("couplesapp://request/\(id.uuidString)") == .request(id))
        #expect(parse("couplesapp://challenge/\(id.uuidString)") == .challenge(id))
        #expect(parse("couplesapp://request/not-a-uuid") == nil)
        #expect(parse("https://example.com/i/abc123") == .invite("abc123"))
        #expect(parse("https://evil.example.org/i/abc123") == nil)
        #expect(parse("https://example.com/guides/x") == nil)
        #expect(parse("couplesapp://invite/ABC123") == .invite("ABC123"))
        #expect(parse("other://unlock") == nil)
    }

    @Test func notificationPrefsAndPremiumRules() throws {
        var prefs = NotificationPrefs()
        #expect(!prefs.weeklyReportEmail) // P24: off by default
        prefs.setMuted(true, for: .kudos)
        prefs.setMuted(true, for: .unlockRequest)
        prefs.setMuted(true, for: .scheduleRequest)
        #expect(prefs.isMuted(.kudos) && !prefs.isMuted(.unlockRequest) && !prefs.isMuted(.scheduleRequest))
        let round = try JSONDecoder().decode(NotificationPrefs.self, from: JSONEncoder().encode(prefs))
        #expect(round == prefs)
        #expect(try JSONDecoder().decode(NotificationPrefs.self, from: Data("{}".utf8)) == NotificationPrefs())

        let pair = UUID()
        let all = [
            Challenge(title: "Free", minutes: 10, category: .kindness, tier: .free),
            Challenge(title: "Library", minutes: 10, category: .movement, tier: .premium),
            Challenge(pairID: pair, title: "Custom", minutes: 30, category: .together, tier: .premium),
            Challenge(title: "Old", minutes: 10, category: .together, tier: .free, status: .archived),
        ]
        #expect(PremiumRules.visibleChallenges(all, isPremium: false).map(\.title) == ["Free"])
        #expect(PremiumRules.visibleChallenges(all, isPremium: true).map(\.title) == ["Free", "Library", "Custom"])
        let schedules = [ProtectedSchedule.standard(), .standard(), .standard()]
        #expect(PremiumRules.effectiveSchedules(schedules, isPremium: false).count == 1)
        #expect(PremiumRules.effectiveSchedules(schedules, isPremium: true).count == 3)
        #expect(Streak(currentLength: 7).isMilestone && !Streak(currentLength: 8).isMilestone)
        #expect(BackendError(rawCode: "over_daily_max").code == .overDailyMax)
        #expect(BackendError(rawCode: "weird").code == .unknown)
    }
}

/// Edge cases kept in step with supabase/tests/edge_cases_test.sql, so the phone's mirror of
/// the ledger and the schedule agree with the server at the corners.
@Suite struct LedgerAndPhaseEdgeTests {
    let calendar = Calendar.gregorian(in: newYork)

    /// 1 November 2026: clocks go back in New York, so the local day lasts 25 hours.
    @Test func dailyMaximumHoldsAcrossTheFallBackDay() throws {
        var l = MinutesLedger(userID: UUID())
        let morning = local(2026, 10, 31, 12, 0)
        l.grant(60, type: .earnChallenge, now: morning, calendar: calendar)
        l.grant(60, type: .earnChallenge, now: morning, calendar: calendar)
        let earlyFallBack = Date(timeIntervalSince1970: 1_793_507_400) // 2026-11-01 04:30 UTC = 00:30 EDT
        try l.spend(45, dailyMax: 60, now: earlyFallBack, calendar: calendar)
        let lateFallBack = local(2026, 11, 1, 23, 30) // 25 hours of local day later, still 1 November
        #expect(throws: MinutesError.overDailyMax) { try l.spend(30, dailyMax: 60, now: lateFallBack, calendar: calendar) }
        try l.spend(15, dailyMax: 60, now: local(2026, 11, 2, 0, 10), calendar: calendar)
    }

    @Test func aCreditExactlyEqualToTheDebtLeavesZero() {
        var l = MinutesLedger(userID: UUID())
        let t0 = local(2026, 10, 10, 20, 0)
        l.borrow(15, now: t0, calendar: calendar)
        l.grant(15, type: .earnKudos, now: t0.addingTimeInterval(86400), calendar: calendar)
        #expect(l.debt == 0 && l.balance == 0 && l.openLots.isEmpty)
        #expect(throws: MinutesError.insufficient) { try l.spend(15, dailyMax: 60, now: t0.addingTimeInterval(86400), calendar: calendar) }
    }

    @Test func expiryIsExactToTheInstant() throws {
        var l = MinutesLedger(userID: UUID())
        let t0 = local(2026, 10, 5, 21, 0)
        l.grant(20, type: .earnKudos, now: t0, calendar: calendar)
        let expiry = t0.addingTimeInterval(7 * 86400)
        #expect(throws: MinutesError.insufficient) { try l.spend(15, dailyMax: 60, now: expiry, calendar: calendar) }
        var earlier = MinutesLedger(userID: UUID())
        earlier.grant(20, type: .earnKudos, now: t0, calendar: calendar)
        try earlier.spend(15, dailyMax: 60, now: expiry.addingTimeInterval(-1), calendar: calendar)
    }

    /// An unlock that runs past the end of protected time ends with protected time: apps are
    /// open either way, and widgets see one change at 9:00, not a second one when the unlock ends.
    @Test func anUnlockOutlastingProtectedTimeEndsWithIt() {
        var state = SharedState()
        state.schedules = [.standard()]
        state.protectionConfigured = true
        let start = local(2026, 11, 11, 8, 30)
        state.activeUnlock = ActiveUnlock(id: UUID(), startedAt: start, endsAt: start.addingTimeInterval(60 * 60))
        let nine = local(2026, 11, 11, 9, 0)
        #expect(state.phase(at: start.addingTimeInterval(60), timeZone: newYork) == .unlocked(until: nine))
        guard case .open = state.phase(at: nine.addingTimeInterval(60), timeZone: newYork) else {
            Issue.record("after 9:00 protected time is over")
            return
        }
        let changes = state.phaseChanges(after: start.addingTimeInterval(60), timeZone: newYork, limit: 2)
        #expect(changes.first == nine)
        #expect(changes.count == 2 && changes[1] == local(2026, 11, 11, 18, 0))
    }
}
