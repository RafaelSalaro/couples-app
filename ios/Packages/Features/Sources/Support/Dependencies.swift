import Backend
import Blocking
import Core
import Foundation
import QRCode

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// Brand values that are not final (decision P22). The app target fills this from `AppBrand`,
/// which reads `Config/Shared.xcconfig`; feature code never hard-codes the name.
public struct BrandInfo: Sendable, Equatable {
    public var displayName: String
    public var urlScheme: String
    public var websiteDomain: String

    public init(displayName: String, urlScheme: String, websiteDomain: String) {
        self.displayName = displayName
        self.urlScheme = urlScheme
        self.websiteDomain = websiteDomain
    }

    public func webURL(_ path: String) -> URL { URL(string: "https://\(websiteDomain)/\(path)")! }
    public var privacyURL: URL { webURL("privacy") }
    public var termsURL: URL { webURL("terms") }
    public var supportURL: URL { webURL("support") }
    public var safetyURL: URL { webURL("safety") }
}

/// Small persistent flags (onboarding progress and the like).
public protocol KeyValueStore: Sendable {
    func string(_ key: String) -> String?
    func set(_ value: String?, for key: String)
}

public final class DefaultsKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func string(_ key: String) -> String? { defaults.string(forKey: key) }
    public func set(_ value: String?, for key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func string(_ key: String) -> String? { lock.withLock { values[key] } }
    public func set(_ value: String?, for key: String) { lock.withLock { values[key] = value } }
}

public struct AppleCredential: Sendable, Equatable {
    public var idToken: String
    public var nonce: String?
    public var fullName: String?

    public init(idToken: String, nonce: String? = nil, fullName: String? = nil) {
        self.idToken = idToken
        self.nonce = nonce
        self.fullName = fullName
    }
}

public enum SignInError: Error, Equatable, Sendable { case cancelled, failed }

/// Runs the Sign in with Apple sheet. The demo implementation returns a fixed credential.
public protocol AppleSignInProviding: Sendable {
    @MainActor func credential() async throws -> AppleCredential
}

public struct DemoAppleSignIn: AppleSignInProviding {
    public init() {}
    public func credential() async throws -> AppleCredential { AppleCredential(idToken: "demo") }
}

/// Notification permission, push registration and the few local notifications the app posts itself.
public protocol NotificationServicing: Sendable {
    /// Asks for permission (with the time-sensitive option) and registers for pushes. Returns whether allowed.
    func requestAuthorization() async -> Bool
    func isAuthorized() async -> Bool
}

public struct DemoNotifications: NotificationServicing {
    public init() {}
    public func requestAuthorization() async -> Bool { true }
    public func isAuthorized() async -> Bool { true }
}

/// Starts and ends the unlock countdown Live Activity (06 §7).
public protocol UnlockActivityControlling: Sendable {
    func start(endsAt: Date, partnerName: String?) async
    func end() async
}

public struct NoUnlockActivity: UnlockActivityControlling {
    public init() {}
    public func start(endsAt: Date, partnerName: String?) async {}
    public func end() async {}
}

/// Everything the features need from outside, assembled once in the app target.
public struct AppDependencies: Sendable {
    public var backend: any Backend
    public var blocking: any BlockingService
    public var store: any SharedStateStore
    public var flags: any KeyValueStore
    public var qrSecrets: any QRSecretStore
    public var usedCounters: any UsedCounterStore
    public var pendingQRUnlocks: PendingQRUnlocks
    public var appleSignIn: any AppleSignInProviding
    public var notifications: any NotificationServicing
    public var unlockActivity: any UnlockActivityControlling
    public var brand: BrandInfo
    public var now: NowProvider
    public var timeZone: @Sendable () -> TimeZone
    /// Asks WidgetKit to redraw after shared state changes.
    public var reloadWidgets: @Sendable () -> Void
    /// Demo builds (in-memory backend): the link a magic-link email would contain, so the flow can be finished without email.
    public var demoMagicLink: (@Sendable (String) -> URL)?
    /// Demo builds and UI tests: a stand-in for scanning, returning what the partner's phone would show.
    public var sampleScan: (@Sendable (SampleScan) -> String?)?

    public enum SampleScan: Sendable { case invite, unlock }

    public init(
        backend: any Backend, blocking: any BlockingService, store: any SharedStateStore,
        flags: any KeyValueStore = InMemoryKeyValueStore(),
        qrSecrets: any QRSecretStore = InMemoryQRSecretStore(),
        usedCounters: any UsedCounterStore = InMemoryUsedCounterStore(),
        pendingQRUnlocks: PendingQRUnlocks = PendingQRUnlocks(defaults: UserDefaults(suiteName: "pending.\(UUID().uuidString)") ?? .standard),
        appleSignIn: any AppleSignInProviding = DemoAppleSignIn(),
        notifications: any NotificationServicing = DemoNotifications(),
        unlockActivity: any UnlockActivityControlling = NoUnlockActivity(),
        brand: BrandInfo = BrandInfo(displayName: "Couples App", urlScheme: "couplesapp", websiteDomain: "example.com"),
        now: @escaping NowProvider = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        reloadWidgets: @escaping @Sendable () -> Void = {},
        demoMagicLink: (@Sendable (String) -> URL)? = nil,
        sampleScan: (@Sendable (SampleScan) -> String?)? = nil
    ) {
        self.backend = backend
        self.blocking = blocking
        self.store = store
        self.flags = flags
        self.qrSecrets = qrSecrets
        self.usedCounters = usedCounters
        self.pendingQRUnlocks = pendingQRUnlocks
        self.appleSignIn = appleSignIn
        self.notifications = notifications
        self.unlockActivity = unlockActivity
        self.brand = brand
        self.now = now
        self.timeZone = timeZone
        self.reloadWidgets = reloadWidgets
        self.demoMagicLink = demoMagicLink
        self.sampleScan = sampleScan
    }
}

/// Friendly, never-scolding wording for things that did not work.
public enum Friendly {
    public static func message(for error: Error) -> String {
        guard let error = error as? BackendError else {
            if let blocking = error as? BlockingError { return message(for: blocking) }
            return L("Something didn't work. Please try again.")
        }
        switch error.code {
        case .offline: return L("You're offline. This needs a connection — try again when you're back.")
        case .alreadyPaired: return L("You're already paired.")
        case .invalid: return L("That didn't match. Check it and try again.")
        case .expired: return L("That one has expired. You can start a new one.")
        case .notPaired, .partnerMissing: return L("Invite your partner to use this.")
        case .rateLimited: return L("That's a few asks in a row. Give it a little while, or use your minutes.")
        case .notPartner: return L("This one is for your partner to answer.")
        case .tooManyAttempts: return L("That code has been tried too many times. You can ask again.")
        case .insufficient: return L("You don't have enough minutes for that yet.")
        case .overDailyMax: return L("That would go past the daily maximum you set.")
        case .inDebt: return L("You borrowed minutes for an emergency unlock. Earn them back first.")
        case .usedThisWeek: return L("You've used this week's emergency unlock.")
        case .duplicateCounter: return L("That code was already used.")
        case .premiumRequired: return L("This is part of premium.")
        case .dailyCap: return L("You've given all of today's kudos. More tomorrow.")
        case .notSignedIn: return L("Please sign in again.")
        case .unknown: return L("Something didn't work. Please try again.")
        }
    }

    public static func message(for error: BlockingError) -> String {
        switch error {
        case .authorizationDenied, .notAuthorized: L("Screen Time access is off. You can turn it on to bring protected time back.")
        case .unlockTooShort: L("Unlocks are at least 15 minutes.")
        case .system: L("Something didn't work. Please try again.")
        }
    }
}
