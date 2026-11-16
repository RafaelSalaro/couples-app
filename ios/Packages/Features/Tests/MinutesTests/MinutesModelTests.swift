import Backend
import Core
import FeatureSupport
import FeatureTestSupport
import Foundation
import Testing
@testable import MinutesFeature

@MainActor @Suite struct MinutesModelTests {
    @Test func timelineShowsWhatExpiresWhen() async {
        // Tuesday Nov 10, 8 PM. The starting 30 minutes expire in exactly 7 days (next Tuesday).
        let app = await TestApp()
        app.world.seedGrant(12, to: TestApp.me, at: testDate(2026, 11, 5, 10)) // expires Thursday Nov 12
        app.world.seedGrant(20, to: TestApp.me, at: testDate(2026, 11, 7, 10)) // expires Saturday Nov 14
        let model = MinutesModel(app: app.model)
        await model.load()
        let buckets = model.buckets(.me)
        #expect(buckets.count == 7)
        #expect(buckets.map(\.minutes) == [0, 12, 0, 20, 0, 0, 30])
        #expect(model.timelineSummary(.me) == "12 min expire Thursday · 20 min Saturday · 30 min Tuesday")
        #expect(model.fraction(buckets[6], in: buckets) == 1)
        #expect(model.fraction(buckets[1], in: buckets) == 0.4)
        #expect(model.fraction(buckets[0], in: buckets) == 0)
        // Partners see each other's balance and its timeline (rule 11).
        #expect(model.buckets(.partner).map(\.minutes) == [0, 0, 0, 0, 0, 0, 30])
        #expect(model.summary(.partner)?.balance == 30)
    }

    @Test func emptyTimelineAndBalanceLines() async throws {
        let app = await TestApp(paired: false)
        let model = MinutesModel(app: app.model)
        await model.load()
        #expect(model.timelineSummary(.me) == "Nothing expires in the next 7 days.")
        #expect(model.balanceLine(.me) == "60 min left to spend today (daily maximum 60 min).")
        // An emergency session borrows only what it used, once it ends (P14): here it runs out.
        _ = try await app.backend.emergencyUnlock(clientEventID: UUID())
        app.clock.advance(15 * 60)
        await model.load()
        #expect(model.balanceLine(.me) == "You borrowed 15 min for an emergency unlock. New minutes repay it first.")
        #expect(model.summary(.partner) == nil)
    }

    @Test func historyIsNewestFirstAndWordedPlainly() async throws {
        let app = await TestApp()
        _ = try await app.backend.spendMinutesUnlock(minutes: 15, clientEventID: UUID())
        let model = MinutesModel(app: app.model)
        await model.load()
        #expect(model.ledger.count == 2)
        #expect(model.title(model.ledger[0]) == "Unlock" && model.amount(model.ledger[0]) == "−15 min")
        #expect(model.title(model.ledger[1]) == "Starting minutes" && model.amount(model.ledger[1]) == "+30 min")
        // Every entry type has a name, and none of them scolds.
        for type in LedgerType.allCases {
            let entry = LedgerEntry(userID: TestApp.me, type: type, minutes: 5, localDay: LocalDay(year: 2026, month: 11, day: 10), createdAt: app.clock.now)
            let title = model.title(entry).lowercased()
            #expect(!title.isEmpty && !title.contains("penalty") && !title.contains("debt"))
        }
    }

    /// Feature spec §7.9: either partner proposes; both must accept.
    @Test func mutualResetProposedByMe() async throws {
        let app = await TestApp()
        app.world.seedGrant(40, to: TestApp.me)
        let model = MinutesModel(app: app.model)
        await model.load()
        #expect(model.canProposeReset && model.standardMinutes == 30)
        await model.proposeReset()
        #expect(model.outgoingReset != nil && model.incomingReset == nil && !model.canProposeReset)
        #expect(app.model.myMinutes?.balance == 70) // nothing changes until the partner agrees
        let proposal = try #require(model.outgoingReset)
        try await app.partner.respondReset(proposalID: proposal.id, accept: true)
        await app.settle()
        #expect(app.model.myMinutes?.balance == 30 && app.model.partnerMinutes?.balance == 30)
        #expect(model.outgoingReset == nil && model.canProposeReset)
    }

    @Test func mutualResetProposedByPartner() async throws {
        let app = await TestApp()
        _ = try await app.partner.proposeReset(standardMinutes: 30)
        await app.settle()
        let model = MinutesModel(app: app.model)
        let proposal = try #require(model.incomingReset)
        await model.respondReset(proposal, accept: false)
        #expect(model.incomingReset == nil && app.model.myMinutes?.balance == 30)
        _ = try await app.partner.proposeReset(standardMinutes: 30)
        await app.settle()
        app.world.seedGrant(25, to: TestApp.me)
        await model.respondReset(try #require(model.incomingReset), accept: true)
        #expect(app.model.myMinutes?.balance == 30)
        #expect(model.title(try #require(model.ledger.first)) == "Fresh start")
    }

    @Test func resetNeedsAPartner() async {
        let app = await TestApp(paired: false)
        #expect(!MinutesModel(app: app.model).canProposeReset)
    }
}
