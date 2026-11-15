import Backend
import Blocking
import Core
import FeatureSupport
import Foundation
import Purchases
import QRCode

/// A controllable clock for tests.
public final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    public init(_ start: Date) { current = start }
    public var now: Date { lock.withLock { current } }
    public func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
    public func set(_ date: Date) { lock.withLock { current = date } }
}

public let testZone = TimeZone(identifier: "America/New_York")!

/// A local wall-clock date in the test time zone.
public func testDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    Calendar.gregorian(in: testZone).date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

/// The whole app wired to the in-memory backend and the mock blocking service:
/// "me" (Rafa) and a partner (Ana) who can act through `partner`.
@MainActor
public struct TestApp {
    public let clock: TestClock
    public let world: FakeWorld
    public let backend: FakeBackend
    public let partner: FakeBackend
    public let store: InMemoryStateStore
    public let blocking: MockBlockingService
    public let flags: InMemoryKeyValueStore
    public let purchases: FakePurchasesService
    public let model: AppModel

    public static let me = FakeWorld.meID
    public static let partnerID = FakeWorld.partnerID

    /// - Parameters:
    ///   - signedIn: whether "me" already has an account and a session.
    ///   - paired: whether the two are paired (implies signed in).
    ///   - ready: whether onboarding is done, Screen Time is granted and apps are chosen.
    ///   - start: the current time; the default (Tuesday 8 PM) is inside the default protected time.
    public init(
        signedIn: Bool = true, paired: Bool = true, premium: Bool = false, ready: Bool = true,
        start: Date = testDate(2026, 11, 10, 20, 0)
    ) async {
        let clock = TestClock(start)
        self.clock = clock
        world = FakeWorld(now: { clock.now })
        world.addPerson(id: FakeWorld.partnerID, name: "Ana", email: "ana@example.com", timeZone: testZone)
        if signedIn || paired {
            world.addPerson(id: FakeWorld.meID, name: "Rafa", email: "rafa@example.com", timeZone: testZone)
        }
        if paired { world.seedPair(FakeWorld.meID, FakeWorld.partnerID, streak: 4) }
        if premium { world.setEntitlement(.subscription, for: FakeWorld.meID) }
        backend = FakeBackend(world: world, signedInAs: signedIn || paired ? FakeWorld.meID : nil)
        partner = FakeBackend(world: world, signedInAs: FakeWorld.partnerID)
        store = InMemoryStateStore()
        blocking = MockBlockingService(store: store, authorization: ready ? .approved : .notDetermined, now: { clock.now }, timeZone: { testZone })
        flags = InMemoryKeyValueStore()
        if ready {
            try? blocking.saveSelection(MockBlockingService.selection(ids: MockBlockingService.suggested))
            flags.set("1", for: "onboarding.done.\(FakeWorld.meID.uuidString)")
        }
        let world = world
        purchases = FakePurchasesService { product, user in
            if let user { world.simulatePurchase(yearly: product == .yearly, by: user) }
        }
        model = AppModel(deps: AppDependencies(
            backend: backend, blocking: blocking, store: store, flags: flags,
            purchases: purchases,
            now: { clock.now }, timeZone: { testZone },
            demoMagicLink: { FakeBackend.magicLink(for: $0, scheme: "couplesapp") },
            sampleScan: { kind in
                switch kind {
                case .invite: world.openInvite(FakeWorld.partnerID)?.code
                case .unlock: (try? world.qrSecret(FakeWorld.partnerID)).flatMap { $0 }.map { QRUnlockPayload(secret: $0, at: clock.now).string }
                }
            }
        ))
        await model.bootstrap()
    }

    /// Lets queued event handling (the model's listening task) run.
    public func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(30))
    }
}
