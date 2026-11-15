import Backend
import Core
import FeatureSupport
import FeatureTestSupport
import Foundation
import Testing
@testable import ChallengesFeature

@MainActor @Suite struct ChallengesModelTests {
    @Test func freeTierShowsTheFivePresetsByCategory() async {
        let app = await TestApp()
        let model = ChallengesModel(app: app.model)
        await model.load()
        #expect(model.sections.flatMap(\.challenges).count == 5)
        #expect(model.sections.map(\.category) == [.together, .kindness, .movement])
        #expect(model.lockedCount == 5) // the sample library in the in-memory backend
        #expect(!model.canCreateCustom)
        let dinner = model.sections[0].challenges[0]
        #expect(dinner.title == "Phone-free dinner together" && model.earnLine(dinner) == "20 min each")
        #expect(model.earnLine(model.sections[1].challenges[0]) == "10 min")
        #expect(ChallengesModel.title(.offlineFun) == "Offline fun")
    }

    @Test func premiumShowsTheLibraryAndCustomChallenges() async {
        let app = await TestApp(premium: true)
        let model = ChallengesModel(app: app.model)
        await model.load()
        #expect(model.sections.flatMap(\.challenges).count == 10)
        #expect(model.sections.map(\.category) == ChallengeCategory.allCases)
        #expect(model.lockedCount == 0 && model.canCreateCustom)
    }

    @Test func doneThenPartnerConfirmsGrantsMinutes() async throws {
        let app = await TestApp()
        let model = ChallengesModel(app: app.model)
        await model.load()
        let note = try #require(model.sections.flatMap(\.challenges).first { $0.title == "Write your partner a note" })
        #expect(await model.markDone(note, note: "  On the fridge "))
        #expect(model.isWaiting(note) && model.waitingForPartner.first?.completion.note == "On the fridge")
        #expect(app.model.myMinutes?.balance == 30) // not before confirmation
        let completion = try #require(model.waitingForPartner.first?.completion)
        try await app.partner.confirmCompletion(id: completion.id)
        await app.settle()
        #expect(!model.isWaiting(note) && app.model.myMinutes?.balance == 40)
    }

    @Test func confirmingThePartnersSharedChallengeGrantsBoth() async throws {
        let app = await TestApp()
        let model = ChallengesModel(app: app.model)
        await model.load()
        let dinner = try #require(model.sections.flatMap(\.challenges).first { $0.isShared })
        _ = try await app.partner.completeChallenge(id: dinner.id, note: "Pasta night")
        await app.settle()
        let pending = try #require(model.toConfirm.first)
        #expect(model.confirmLine(pending) == "Ana did “Phone-free dinner together”")
        await model.confirm(pending)
        #expect(model.toConfirm.isEmpty)
        #expect(app.model.myMinutes?.balance == 50 && app.model.partnerMinutes?.balance == 50)
    }

    @Test func previewBeforeThePartnerJoins() async throws {
        let app = await TestApp(paired: false)
        let model = ChallengesModel(app: app.model)
        await model.load()
        #expect(model.sections.flatMap(\.challenges).count == 5 && !model.canComplete)
        let first = try #require(model.sections.first?.challenges.first)
        #expect(!(await model.markDone(first, note: "")))
        #expect(model.message == "Invite your partner to use this.")
    }

    @Test func customChallengeValueIsAgreedTogether() async throws {
        let app = await TestApp(premium: true)
        let model = ChallengesModel(app: app.model)
        #expect(!model.isValidCustom(title: "  ", minutes: 30))
        #expect(!model.isValidCustom(title: "Fix the bike", minutes: 65))
        #expect(model.isValidCustom(title: "Fix the bike", minutes: 30))
        #expect(await model.createCustom(title: "Fix the bike together", description: "", minutes: 30, category: .together, isShared: true))
        let mine = try #require(model.valuesWaiting.first)
        #expect(model.valuesToAnswer.isEmpty && !model.sections.flatMap(\.challenges).contains(mine))
        // The partner suggests 20 instead; now it is mine to answer.
        _ = try await app.partner.respondChallengeValue(challengeID: mine.id, approve: false, counterMinutes: 20)
        await app.settle()
        let countered = try #require(model.valuesToAnswer.first)
        #expect(model.valueQuestion(countered) == "Ana suggests 20 min for “Fix the bike together” — sounds right?")
        await model.answerValue(countered, approve: true)
        #expect(model.valuesToAnswer.isEmpty)
        #expect(model.sections.flatMap(\.challenges).contains { $0.title == "Fix the bike together" && $0.minutes == 20 })
    }

    @Test func partnersCustomChallengeAsksMe() async throws {
        let app = await TestApp(premium: true)
        _ = try await app.partner.createCustomChallenge(title: "Fix the bike together", description: "", minutes: 30, category: .together, isShared: true)
        await app.settle()
        let model = ChallengesModel(app: app.model)
        let proposed = try #require(model.valuesToAnswer.first)
        #expect(model.valueQuestion(proposed) == "Ana added “Fix the bike together” for 30 min — sounds right?")
        await model.answerValue(proposed, approve: false, counterMinutes: 45)
        #expect(model.valuesWaiting.first?.minutes == 45)
    }

    @Test func downgradeHidesCustomChallengesAndTheyReturn() async throws {
        let app = await TestApp(premium: true)
        let model = ChallengesModel(app: app.model)
        _ = await model.createCustom(title: "Fix the bike together", description: "", minutes: 30, category: .together, isShared: true)
        let custom = try #require(model.valuesWaiting.first)
        _ = try await app.partner.respondChallengeValue(challengeID: custom.id, approve: true, counterMinutes: nil)
        await app.settle()
        #expect(model.sections.flatMap(\.challenges).contains { $0.isCustom })
        app.world.setEntitlement(nil, for: TestApp.me)
        await app.settle()
        #expect(!model.sections.flatMap(\.challenges).contains { $0.isCustom })
        #expect(app.model.challenges.contains { $0.isCustom }) // hidden, not deleted
        app.world.setEntitlement(.subscription, for: TestApp.me)
        await app.settle()
        #expect(model.sections.flatMap(\.challenges).contains { $0.isCustom })
    }
}
