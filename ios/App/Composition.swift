import Backend
import Blocking
import Core
import FeatureSupport
import Foundation
import QRCode
import UIKit
import WidgetKit

/// Launch arguments that select the in-memory backend and its starting situation.
/// Used by UI tests and when no Supabase project is configured (the Simulator demo).
///
///   -demo 1                      use the in-memory backend even if Supabase is configured
///   -uiTest 1                    demo + no animations
///   -scenario fresh|onboarded|paired
///   -premium 1                   the user has an active subscription
///   -phase protected|open        make "now" fall inside or outside protected time
///   -partner yes|no|silent       how the scripted partner answers
///   -partnerActions a,b          things the partner does unprompted (see FakePartnerBot.Action)
///   -partnerPushOff 1            the partner has notifications off (email fallback at once)
///   -screenTime deny             the Screen Time prompt is declined
///   -streak N                    seeded shared streak
struct LaunchOptions: Equatable {
    enum Scenario: String { case fresh, onboarded, paired }
    enum Phase: String { case protected, open }

    var demo = false
    var uiTest = false
    var scenario = Scenario.fresh
    var premium = false
    var phase: Phase?
    var partnerAnswer = FakePartnerBot.Behavior.Answer.yes
    var partnerActions: [FakePartnerBot.Action] = []
    var partnerPushOff = false
    var screenTimeDenied = false
    var streak = 4

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: "-\(name)"), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        uiTest = value("uiTest") == "1"
        demo = uiTest || value("demo") == "1"
        scenario = value("scenario").flatMap(Scenario.init(rawValue:)) ?? .fresh
        premium = value("premium") == "1"
        phase = value("phase").flatMap(Phase.init(rawValue:))
        partnerAnswer = value("partner").flatMap(FakePartnerBot.Behavior.Answer.init(rawValue:)) ?? .yes
        partnerActions = (value("partnerActions") ?? "").split(separator: ",").compactMap { FakePartnerBot.Action(rawValue: String($0)) }
        partnerPushOff = value("partnerPushOff") == "1"
        screenTimeDenied = value("screenTime") == "deny"
        streak = value("streak").flatMap(Int.init) ?? 4
    }
}

/// Builds the dependencies once at launch: the real services, or the demo ones.
@MainActor
enum Composition {
    static func make(options: LaunchOptions = LaunchOptions()) -> AppModel {
        let store = AppGroupStateStore()
        let reload: @Sendable () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
        guard !options.demo, let supabase = AppConfig.supabase else {
            return demo(options: options, store: store, reloadWidgets: reload)
        }
        let backend = SupabaseBackend(
            url: supabase.url, anonKey: supabase.anonKey,
            redirectURL: URL(string: "\(AppBrand.urlScheme)://login-callback")
        )
        return AppModel(deps: AppDependencies(
            backend: backend,
            blocking: BlockingServiceFactory.make(store: store),
            store: store,
            flags: DefaultsKeyValueStore(),
            qrSecrets: KeychainQRSecretStore(),
            usedCounters: DefaultsUsedCounterStore(),
            pendingQRUnlocks: PendingQRUnlocks(),
            appleSignIn: SystemAppleSignIn(),
            notifications: SystemNotifications(),
            brand: AppBrand.info,
            reloadWidgets: reload
        ))
    }

    /// The in-memory world: "you" and a scripted partner, Ana. Everything resets on each launch.
    static func demo(options: LaunchOptions, store: AppGroupStateStore, reloadWidgets: @escaping @Sendable () -> Void) -> AppModel {
        if options.uiTest { UIView.setAnimationsEnabled(false) }
        if let bundleID = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: bundleID) }
        store.reset()

        let world = FakeWorld(websiteDomain: AppBrand.websiteDomain)
        let me = FakeWorld.meID, partner = FakeWorld.partnerID
        world.addPerson(id: partner, name: "Ana", email: "ana@example.com")
        world.setPushEnabled(!options.partnerPushOff, for: partner)
        let flags = DefaultsKeyValueStore()
        let blocking = MockBlockingService(store: store, authorization: options.scenario == .fresh ? .notDetermined : .approved)
        if options.screenTimeDenied { blocking.setAuthorizationOutcome(.denied) }

        if options.scenario != .fresh {
            world.addPerson(id: me, name: "Rafa", email: "rafa@example.com")
            flags.set("1", for: "onboarding.done.\(me.uuidString)")
            try? blocking.saveSelection(MockBlockingService.selection(ids: MockBlockingService.suggested))
            if let phase = options.phase {
                world.seedSchedules([schedule(for: phase)], for: me)
            }
        }
        if options.scenario == .paired {
            world.seedPair(me, partner, streak: options.streak)
        } else {
            // So "join with a code" can be tried: Ana has an invite waiting.
            world.seedInvite(from: partner, code: "ANA234", token: "demoinvite")
        }
        if options.premium, options.scenario != .fresh { world.setEntitlement(.subscription, for: me) }

        let backend = FakeBackend(world: world, signedInAs: options.scenario == .fresh ? nil : me)
        var behavior = FakePartnerBot.Behavior()
        for keyPath in [\FakePartnerBot.Behavior.unlockRequests, \.completions, \.scheduleChanges, \.resets, \.challengeValues] {
            behavior[keyPath: keyPath] = options.partnerAnswer
        }
        behavior.acceptsInvite = options.partnerAnswer == .yes
        let bot = FakePartnerBot(backend: FakeBackend(world: world, signedInAs: partner), userBackend: backend, behavior: behavior)
        bot.start(actions: options.partnerActions)

        let scheme = AppBrand.urlScheme
        return AppModel(deps: AppDependencies(
            backend: backend, blocking: blocking, store: store, flags: flags,
            usedCounters: InMemoryUsedCounterStore(),
            brand: AppBrand.info,
            reloadWidgets: reloadWidgets,
            demoMagicLink: { FakeBackend.magicLink(for: $0, scheme: scheme) },
            sampleScan: { kind in
                switch kind {
                case .invite: world.openInvite(partner)?.code
                case .unlock: (try? world.qrSecret(partner)).flatMap { $0 }.map { QRUnlockPayload(secret: $0, at: Date()).string }
                }
            }
        ))
    }

    /// A schedule that makes the current moment protected (started an hour ago) or open (starts in three hours).
    static func schedule(for phase: LaunchOptions.Phase, now: Date = Date(), calendar: Calendar = .current) -> ProtectedSchedule {
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        switch phase {
        case .protected:
            return ProtectedSchedule(startLocal: LocalTime(minutesFromMidnight: minutes - 60), endLocal: LocalTime(minutesFromMidnight: minutes + 180))
        case .open:
            return ProtectedSchedule(startLocal: LocalTime(minutesFromMidnight: minutes + 180), endLocal: LocalTime(minutesFromMidnight: minutes + 300))
        }
    }
}
