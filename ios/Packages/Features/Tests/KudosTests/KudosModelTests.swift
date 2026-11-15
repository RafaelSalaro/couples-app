import Backend
import Core
import FeatureSupport
import FeatureTestSupport
import Foundation
import Testing
@testable import KudosFeature

@MainActor @Suite struct KudosModelTests {
    @Test func givingKudosGrantsThePartner() async {
        let app = await TestApp(premium: true)
        let model = KudosModel(app: app.model)
        await model.load()
        #expect(model.amounts == [5, 10, 15, 20, 25, 30] && model.minutes == 10 && model.remainingToday == 60)
        model.note = model.suggestions[0]
        #expect(model.canGive)
        await model.give()
        #expect(model.sent?.minutes == 10 && model.sent?.message == "You made me laugh today")
        #expect(model.sentLine == "Ana just got 10 min from you.")
        #expect(app.model.partnerMinutes?.balance == 40)
    }

    /// Feature spec §8: free-form kudos 5–30 minutes, capped at 60 minutes per giver per day.
    @Test func dailyCap() async throws {
        let app = await TestApp(premium: true)
        _ = try await app.backend.giveKudos(minutes: 30, message: "", challengeID: nil)
        _ = try await app.backend.giveKudos(minutes: 20, message: "", challengeID: nil)
        let model = KudosModel(app: app.model)
        model.minutes = 30
        await model.load()
        #expect(model.remainingToday == 10 && model.minutes == 10) // falls back to what still fits
        #expect(model.remainingLine == "10 min of kudos left to give today.")
        await model.give()
        let after = KudosModel(app: app.model)
        await after.load()
        #expect(after.remainingToday == 0 && !after.canGive)
        #expect(after.remainingLine == "You've given all of today's kudos. More tomorrow.")
        // Kudos the partner gave do not count against my cap.
        _ = try await app.partner.giveKudos(minutes: 30, message: "", challengeID: nil)
        await after.load()
        #expect(after.remainingToday == 0)
        app.clock.set(testDate(2026, 11, 11, 9))
        await after.load()
        #expect(after.remainingToday == 60)
    }

    @Test func kudosArePremiumAndNeedAPartner() async {
        let free = await TestApp()
        let model = KudosModel(app: free.model)
        #expect(!model.isPremium && !model.canGive)
        await model.give()
        #expect(model.sent == nil && model.message == "This is part of premium.")
        let alone = await TestApp(paired: false, premium: true)
        #expect(!KudosModel(app: alone.model).canGive)
    }

    @Test func kudosFromAChallengeStartsFromItsTitleAndValue() async throws {
        let app = await TestApp(premium: true)
        let dinner = try #require(app.model.challenges.first { $0.title == "Phone-free dinner together" })
        let model = KudosModel(app: app.model, challengeID: dinner.id)
        #expect(model.minutes == 20 && model.note == dinner.title)
        await model.give()
        #expect(model.sent?.challengeID == dinner.id)
        // Values above the kudos range are capped at 30.
        let long = Challenge(title: "Day trip", minutes: 60, category: .together)
        #expect(MinutesRules.kudosRange.contains(min(max(5, long.minutes / 5 * 5), 30)))
    }

    @Test func receivedKudosWording() {
        let kudos = Kudos(id: UUID(), pairID: UUID(), giverID: UUID(), receiverID: UUID(), message: "You made me laugh today", minutes: 10, createdAt: Date())
        #expect(KudosText.title(from: "Ana") == "Kudos from Ana")
        #expect(KudosText.body(kudos, partnerName: "Ana") == "“You made me laugh today”")
        #expect(KudosText.amount(kudos) == "+10 min")
        var silent = kudos
        silent.message = ""
        #expect(KudosText.body(silent, partnerName: "Ana") == "Ana noticed you.")
    }
}
