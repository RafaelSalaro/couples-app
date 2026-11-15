import Backend
import Blocking
import Core
import FeatureSupport
import FeatureTestSupport
import Foundation
import Testing
@testable import ScheduleFeature

@MainActor @Suite struct ScheduleModelTests {
    let en = Locale(identifier: "en_US")

    func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ") }

    /// Feature spec §4: stricter changes apply immediately.
    @Test func longerProtectedTimeAppliesNow() async throws {
        let app = await TestApp()
        let model = ScheduleModel(app: app.model)
        var draft = try #require(model.schedules.first)
        #expect(model.effect(of: draft) == .nothing)
        draft.startLocal = LocalTime(hour: 17)
        #expect(model.effect(of: draft) == .appliesNow)
        #expect(model.effectLine(.appliesNow) == "This applies right away.")
        #expect(await model.save(draft))
        #expect(app.model.schedules.first?.startLocal == LocalTime(hour: 17) && model.savedNote == "Saved.")
        #expect(app.store.load().schedules.first?.startLocal == LocalTime(hour: 17))
    }

    /// Looser changes need the partner: shortening hours, removing days, turning it off.
    @Test func shorterProtectedTimeAsksThePartner() async throws {
        let app = await TestApp()
        let model = ScheduleModel(app: app.model)
        let original = try #require(model.schedules.first)
        var later = original
        later.startLocal = LocalTime(hour: 19)
        var fewerDays = original
        fewerDays.weekdays = [1, 2, 3, 4, 5]
        var off = original
        off.enabled = false
        for draft in [later, fewerDays, off] { #expect(model.effect(of: draft) == .needsPartner) }
        #expect(model.effectLine(.needsPartner)?.contains("Ana will be asked") == true)
        #expect(await model.save(later))
        #expect(model.savedNote == "Ana will be asked. You'll hear back within 24 hours.")
        #expect(app.model.schedules.first == original) // unchanged until approved
        let request = try #require(model.waiting.first)
        #expect(plain(model.describe(request, locale: en)) == "You asked for protected time to be 7:00 PM – 9:00 AM, every day.")
        try await app.partner.respondScheduleChange(requestID: request.id, approve: true)
        await app.settle()
        #expect(app.model.schedules.first?.startLocal == LocalTime(hour: 19) && model.waiting.isEmpty)
        #expect(app.store.load().schedules.first?.startLocal == LocalTime(hour: 19))
    }

    @Test func unpairedChangesAlwaysApplyNow() async throws {
        let app = await TestApp(paired: false)
        let model = ScheduleModel(app: app.model)
        var draft = try #require(model.schedules.first)
        draft.enabled = false
        #expect(model.effect(of: draft) == .appliesNow)
        #expect(await model.save(draft))
        #expect(app.model.schedules.first?.enabled == false)
        #expect(!app.blocking.isProtectedNow())
    }

    @Test func answeringThePartnersRequest() async throws {
        let app = await TestApp()
        var theirs = try #require(try await app.partner.fetchSchedules().first)
        theirs.startLocal = LocalTime(hour: 19)
        _ = try await app.partner.submitScheduleChange(scheduleID: theirs.id, proposal: .schedule(theirs))
        await app.settle()
        let model = ScheduleModel(app: app.model)
        let request = try #require(model.toAnswer.first)
        #expect(plain(model.describe(request, locale: en)) == "Ana would like protected time to be 7:00 PM – 9:00 AM, every day.")
        await model.respond(request, approve: false) // "Let's talk"
        #expect(model.toAnswer.isEmpty)
        #expect(try await app.partner.fetchSchedules().first?.startLocal == LocalTime(hour: 18))
        theirs.enabled = false
        _ = try await app.partner.submitScheduleChange(scheduleID: theirs.id, proposal: .schedule(theirs))
        await app.settle()
        let off = try #require(model.toAnswer.first)
        #expect(model.describe(off) == "Ana would like to turn protected time off.")
        await model.respond(off, approve: true)
        #expect(try await app.partner.fetchSchedules().first?.enabled == false)
    }

    @Test func otherRequestWording() async {
        let app = await TestApp()
        let model = ScheduleModel(app: app.model)
        func request(_ proposal: ScheduleProposal, mine: Bool) -> ScheduleChangeRequest {
            ScheduleChangeRequest(id: UUID(), pairID: UUID(), requesterID: mine ? TestApp.me : TestApp.partnerID, scheduleID: nil, proposed: proposal, expiresAt: app.clock.now, createdAt: app.clock.now)
        }
        // The partner is told "fewer apps" and nothing else.
        #expect(model.describe(request(.fewerPausedApps, mine: false)) == "Ana would like to pause fewer apps.")
        #expect(model.describe(request(.fewerPausedApps, mine: true)) == "You asked to pause fewer apps.")
        #expect(model.describe(request(.removeSchedule, mine: false)) == "Ana would like to remove one of their protected times.")
    }

    @Test func extraSchedulesArePremium() async throws {
        let free = await TestApp()
        #expect(!ScheduleModel(app: free.model).canAdd)
        let app = await TestApp(premium: true)
        let model = ScheduleModel(app: app.model)
        #expect(model.canAdd)
        let lunch = ProtectedSchedule(name: "Lunch", weekdays: [1, 2, 3, 4, 5], startLocal: LocalTime(hour: 12), endLocal: LocalTime(hour: 13))
        #expect(model.effect(of: lunch) == .appliesNow && model.isValid(lunch))
        #expect(await model.save(lunch))
        #expect(model.schedules.count == 2 && !model.isResting(lunch))
        var noDays = lunch
        noDays.weekdays = []
        #expect(!model.isValid(noDays))
        // Removing one is looser.
        await model.remove(lunch)
        #expect(model.schedules.count == 2 && model.waiting.count == 1)
        // Without premium the extra one rests; it is not deleted.
        app.world.setEntitlement(nil, for: TestApp.me)
        await app.settle()
        #expect(model.isResting(lunch) && model.schedules.count == 2)
    }

    @Test func pausedApps() async throws {
        let app = await TestApp()
        let model = ScheduleModel(app: app.model)
        #expect(model.selectionSummary == "1 category · 1 website")
        let current = app.blocking.currentSelection()
        #expect(model.selectionEffect(current) == .nothing)
        let more = MockBlockingService.selection(ids: MockBlockingService.suggested.union(["category.games", "app.news"]))
        #expect(model.selectionEffect(more) == .appliesNow)
        #expect(await model.saveSelection(more))
        #expect(model.selectionSummary == "2 categories · 1 app · 1 website")
        let fewer = MockBlockingService.selection(ids: ["category.social"])
        #expect(model.selectionEffect(fewer) == .needsPartner)
        #expect(model.selectionEffectLine(.needsPartner)?.contains("without seeing which apps") == true)
        #expect(await model.saveSelection(fewer))
        #expect(app.blocking.currentSelection() == more)
        #expect(model.waiting.first?.proposed == .fewerPausedApps)
    }
}
