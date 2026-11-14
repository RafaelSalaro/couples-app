import Core
import DeviceActivity
import Foundation
import Testing
@testable import Blocking

let zone = TimeZone(identifier: "America/New_York")!
func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    Calendar.gregorian(in: zone).date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

struct MockFixture {
    let store = InMemoryStateStore()
    let clock = Clock(at(2026, 11, 10, 20, 0))
    let service: MockBlockingService

    init(authorization: BlockingAuthorization = .approved, configured: Bool = true) {
        let clock = clock
        service = MockBlockingService(store: store, authorization: authorization, now: { clock.now }, timeZone: { zone })
        if configured {
            try? service.saveSelection(MockBlockingService.selection(ids: MockBlockingService.suggested))
            try? service.applySchedule([.standard()])
        }
    }
}

@Suite struct MockBlockingServiceTests {
    @Test func authorization() async throws {
        let f = MockFixture(authorization: .notDetermined, configured: false)
        #expect(f.service.authorizationStatus == .notDetermined && f.service.needsAuthorization)
        #expect(throws: BlockingError.notAuthorized) { try f.service.saveSelection(MockBlockingService.selection(ids: ["category.social"])) }
        try await f.service.requestAuthorization()
        #expect(f.service.authorizationStatus == .approved)
        f.service.setAuthorizationOutcome(.denied)
        await #expect(throws: BlockingError.authorizationDenied) { try await f.service.requestAuthorization() }
        #expect(f.service.authorizationStatus == .denied)
    }

    @Test func protectedOnlyInsideTheScheduleOnceConfigured() throws {
        let f = MockFixture(configured: false)
        try f.service.applySchedule([.standard()])
        #expect(!f.service.isProtectedNow()) // nothing chosen yet
        try f.service.saveSelection(MockBlockingService.selection(ids: MockBlockingService.suggested))
        #expect(f.service.isProtectedNow())
        #expect(f.store.load().protectionConfigured && f.store.load().mockShieldApplied)
        f.clock.now = at(2026, 11, 11, 12)
        #expect(!f.service.isProtectedNow())
        f.clock.now = at(2026, 11, 11, 8, 59)
        #expect(f.service.isProtectedNow())
        f.clock.now = at(2026, 11, 11, 9)
        #expect(!f.service.isProtectedNow())
    }

    @Test func selectionIsStoredOpaqueAndCounted() throws {
        let f = MockFixture()
        let selection = try #require(f.service.currentSelection())
        #expect(selection.categoryCount == 1 && selection.webDomainCount == 1 && selection.applicationCount == 0 && !selection.isEmpty)
        #expect(MockBlockingService.ids(of: selection) == MockBlockingService.suggested)
        #expect(f.store.loadSelectionData() != nil)
        // Nothing about the selection is in the shared state other extensions and the server see.
        let json = String(decoding: try JSONEncoder().encode(f.store.load()), as: UTF8.self)
        #expect(!json.contains("social"))
    }

    @Test func unlockOpensThenProtectionResumes() throws {
        let f = MockFixture()
        let id = UUID()
        try f.service.startUnlock(id: id, minutes: 15)
        #expect(!f.service.isProtectedNow())
        #expect(f.store.load().activeUnlock?.endsAt == f.clock.now.addingTimeInterval(900))
        f.clock.now += 899
        #expect(!f.service.isProtectedNow())
        f.clock.now += 1
        #expect(f.service.isProtectedNow())
        #expect(f.store.load().activeUnlock == nil)
    }

    @Test func minimumFifteenMinutesAndExtension() throws {
        let f = MockFixture()
        #expect(throws: BlockingError.unlockTooShort) { try f.service.startUnlock(id: UUID(), minutes: 10) }
        try f.service.startUnlock(id: UUID(), minutes: 30)
        f.clock.now += 600
        let second = UUID()
        try f.service.startUnlock(id: second, minutes: 15)
        let unlock = try #require(f.store.load().activeUnlock)
        #expect(unlock.id == second && unlock.endsAt == at(2026, 11, 10, 20, 45))
    }

    @Test func endingEarlyBringsThePauseBack() throws {
        let f = MockFixture()
        let id = UUID()
        try f.service.startUnlock(id: id, minutes: 30)
        try f.service.endUnlockEarly(id: UUID()) // someone else's id: ignored
        #expect(!f.service.isProtectedNow())
        try f.service.endUnlockEarly(id: id)
        #expect(f.service.isProtectedNow())
    }

    @Test func revokingAccessTurnsProtectionOff() {
        let f = MockFixture()
        #expect(f.service.isProtectedNow())
        f.service.revokeAuthorization()
        #expect(!f.service.isProtectedNow() && f.service.needsAuthorization)
        #expect(!f.store.load().protectionConfigured)
    }

    @Test func fewerAppsIsLooserMoreIsStricter() {
        let f = MockFixture()
        let social = MockBlockingService.selection(ids: ["category.social"])
        let both = MockBlockingService.selection(ids: ["category.social", "category.games"])
        let games = MockBlockingService.selection(ids: ["category.games"])
        #expect(f.service.selectionChange(from: social, to: both) == .stricter)
        #expect(f.service.selectionChange(from: both, to: social) == .looser)
        #expect(f.service.selectionChange(from: social, to: games) == .looser) // swapping loses one
        #expect(f.service.selectionChange(from: social, to: social) == .same)
        #expect(f.service.selectionChange(from: nil, to: social) == .stricter)
    }
}

@Suite struct ShieldContentTests {
    func state(partner: String? = "Ana") -> SharedState {
        var state = SharedState()
        state.schedules = [.standard()]
        state.protectionConfigured = true
        state.partnerName = partner
        return state
    }

    @Test func pauseScreenCopy() {
        let content = ShieldContent.make(state: state(), now: at(2026, 11, 10, 20, 46), timeZone: zone, lineIndex: 0)
        #expect(content.title == "Protected time")
        #expect(content.subtitle == "12h 14m left\nWant to do something together?")
        #expect(content.primaryButton == "Ask Ana")
        #expect(content.secondaryButton == "Not now")
    }

    @Test func linesRotateAndUseThePartnersName() {
        let lines = (0..<4).map { ShieldContent.invitingLine($0, partner: "Ana") }
        #expect(Set(lines).count == 4)
        #expect(lines[1] == "Ana is around — say hi?")
        #expect(ShieldContent.invitingLine(5, partner: "Ana") == lines[1])
        // Without a partner the lines never mention one.
        #expect((0..<4).allSatisfy { !ShieldContent.invitingLine($0, partner: nil).contains("nil") })
        let a = ShieldContent.make(state: state(), now: at(2026, 11, 10, 20, 0), timeZone: zone)
        let b = ShieldContent.make(state: state(), now: at(2026, 11, 10, 20, 10), timeZone: zone)
        #expect(a.subtitle.split(separator: "\n").last != b.subtitle.split(separator: "\n").last)
    }

    @Test func unpairedCopyAndVocabulary() {
        let content = ShieldContent.make(state: state(partner: nil), now: at(2026, 11, 10, 20), timeZone: zone, lineIndex: 1)
        #expect(content.primaryButton == "Unlock options")
        let prompt = ShieldPrompt.make(state: state(partner: nil), urlScheme: "couplesapp")
        #expect(prompt.body == "Tap to see your unlock options")
        let paired = ShieldPrompt.make(state: state(), urlScheme: "couplesapp")
        #expect(paired.body == "Tap to ask Ana or use your minutes")
        #expect(paired.deepLink == URL(string: "couplesapp://unlock"))
        // Vocabulary rule: never "blocked", "denied" or "permission".
        for text in [content.title, content.subtitle, content.primaryButton, content.secondaryButton, prompt.body, paired.body] {
            let lower = text.lowercased()
            #expect(!lower.contains("block") && !lower.contains("denied") && !lower.contains("permission"))
        }
    }
}

@Suite struct ScreenTimePlanningTests {
    @Test func everyDayScheduleIsOneRepeatingInterval() {
        let plans = SchedulePlanner.plans(for: .standard())
        #expect(plans == [MonitorPlan(part: "all", start: DateComponents(hour: 18, minute: 0), end: DateComponents(hour: 9, minute: 0))])
    }

    @Test func weekdaySchedulesGetOneMonitorPerStartDay() {
        // Friday and Saturday nights, 22:00–06:00.
        let schedule = ProtectedSchedule(weekdays: [5, 6], startLocal: LocalTime(hour: 22), endLocal: LocalTime(hour: 6))
        let plans = SchedulePlanner.plans(for: schedule)
        #expect(plans.count == 2)
        // Friday is calendar weekday 6; it ends Saturday (7). Saturday (7) ends Sunday (1).
        #expect(plans[0] == MonitorPlan(part: "5", start: DateComponents(hour: 22, minute: 0, weekday: 6), end: DateComponents(hour: 6, minute: 0, weekday: 7)))
        #expect(plans[1].start.weekday == 7 && plans[1].end.weekday == 1)
        let daytime = ProtectedSchedule(weekdays: [7], startLocal: LocalTime(hour: 9), endLocal: LocalTime(hour: 12))
        #expect(SchedulePlanner.plans(for: daytime).first?.end.weekday == 1) // Sunday stays Sunday
    }

    @Test func midnightSplitFallback() {
        let plans = SchedulePlanner.plans(for: .standard(), splitAtMidnight: true)
        #expect(plans.map(\.part) == ["all-a", "all-b"])
        #expect(plans[0].end == DateComponents(hour: 23, minute: 59) && plans[1].start == DateComponents(hour: 0, minute: 0))
        #expect(plans[1].end == DateComponents(hour: 9, minute: 0))
        let daytime = ProtectedSchedule(startLocal: LocalTime(hour: 9), endLocal: LocalTime(hour: 12))
        #expect(SchedulePlanner.plans(for: daytime, splitAtMidnight: true).count == 1)
    }

    @Test func disabledSchedulesRegisterNothing() {
        var schedule = ProtectedSchedule.standard()
        schedule.enabled = false
        #expect(SchedulePlanner.plans(for: schedule).isEmpty)
    }

    @Test func activityNames() {
        let id = UUID()
        #expect(ActivityNames.unlockID(ActivityNames.unlock(id)) == id)
        #expect(ActivityNames.isProtected(ActivityNames.protected(id, part: "all")))
        #expect(!ActivityNames.isProtected(ActivityNames.unlock(id)))
        #expect(ActivityNames.unlockID(ActivityNames.protected(id, part: "all")) == nil)
    }

    @Test func shieldDecision() {
        var state = SharedState()
        state.schedules = [.standard()]
        let night = at(2026, 11, 10, 22)
        #expect(!ShieldController.shouldShield(state: state, at: night, timeZone: zone)) // not configured
        state.protectionConfigured = true
        #expect(ShieldController.shouldShield(state: state, at: night, timeZone: zone))
        #expect(!ShieldController.shouldShield(state: state, at: at(2026, 11, 10, 12), timeZone: zone))
        state.activeUnlock = ActiveUnlock(id: UUID(), startedAt: night, endsAt: night.addingTimeInterval(900))
        #expect(!ShieldController.shouldShield(state: state, at: night.addingTimeInterval(60), timeZone: zone))
        #expect(ShieldController.shouldShield(state: state, at: night.addingTimeInterval(900), timeZone: zone))
        // A callback that fires a few seconds early still sees the schedule as started.
        let early = at(2026, 11, 10, 18).addingTimeInterval(-5)
        state.activeUnlock = nil
        #expect(!ShieldController.shouldShield(state: state, at: early, timeZone: zone))
        #expect(ShieldController.shouldShield(state: state, at: early.addingTimeInterval(ShieldController.callbackTolerance), timeZone: zone))
    }

    @Test func buildConfigurationSelectsTheService() {
        #expect(BlockingServiceFactory.resolve(setting: "mock") == .mock)
        #expect(BlockingServiceFactory.resolve(setting: "screentime") == .screenTime)
        #expect(BlockingServiceFactory.resolve(setting: nil) == .screenTime)
        // The Simulator always gets the mock: Screen Time does nothing there.
        #expect(BlockingServiceFactory.configuredKind(info: ["BlockingServiceKind": "screentime"], arguments: []) == .mock)
        #expect(BlockingServiceFactory.make(kind: .mock, store: InMemoryStateStore()).kind == .mock)
        #expect(BlockingServiceFactory.make(kind: .screenTime, store: InMemoryStateStore()).kind == .screenTime)
    }
}
