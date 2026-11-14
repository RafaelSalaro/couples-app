import Core
import CryptoKit
import Foundation

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// Time-based one-time codes (RFC 6238: HMAC-SHA1, 30-second step, 6 digits) for the in-person QR unlock.
public enum TOTP {
    public static let step: TimeInterval = 30
    public static let digits = 6
    /// Codes from one step before or after are accepted (clock drift between the two phones).
    public static let tolerance: Int64 = 1

    public static func counter(at date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 / step).rounded(.down))
    }

    /// RFC 4226 HOTP value for a counter.
    public static func code(secret: Data, counter: Int64) -> String {
        var bigEndian = UInt64(bitPattern: counter).bigEndian
        let message = Data(bytes: &bigEndian, count: 8)
        let mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let binary = (UInt32(mac[offset] & 0x7F) << 24) | (UInt32(mac[offset + 1]) << 16) | (UInt32(mac[offset + 2]) << 8) | UInt32(mac[offset + 3])
        let value = binary % 1_000_000
        return String(format: "%06d", value)
    }

    public static func code(secret: Data, at date: Date) -> String {
        code(secret: secret, counter: counter(at: date))
    }

    /// Seconds until the current code changes, and the fraction of the step already used (for the progress ring).
    public static func secondsRemaining(at date: Date) -> TimeInterval {
        step - date.timeIntervalSince1970.truncatingRemainder(dividingBy: step)
    }

    public static func progress(at date: Date) -> Double {
        1 - secondsRemaining(at: date) / step
    }
}

/// What the rotating QR code carries: the pair, the time-step counter and the 6-digit code (04 §3.4).
public struct QRUnlockPayload: Equatable, Sendable {
    public static let prefix = "couples-unlock"
    public var pairID: UUID
    public var counter: Int64
    public var code: String

    public init(pairID: UUID, counter: Int64, code: String) {
        self.pairID = pairID
        self.counter = counter
        self.code = code
    }

    public init(secret: QRSecret, at date: Date) {
        let counter = TOTP.counter(at: date)
        self.init(pairID: secret.pairID, counter: counter, code: TOTP.code(secret: secret.secret, counter: counter))
    }

    public var string: String { "\(Self.prefix):1:\(pairID.uuidString.lowercased()):\(counter):\(code)" }

    public init?(_ string: String) {
        let parts = string.split(separator: ":").map(String.init)
        guard parts.count == 5, parts[0] == Self.prefix, parts[1] == "1", let pair = UUID(uuidString: parts[2]),
              let counter = Int64(parts[3]), parts[4].count == TOTP.digits, parts[4].allSatisfy(\.isNumber) else { return nil }
        self.init(pairID: pair, counter: counter, code: parts[4])
    }
}

public enum QRVerificationError: Error, Equatable, Sendable {
    /// Not one of our unlock codes at all.
    case unrecognized
    /// A code from a different pair.
    case differentPair
    /// The code is from too long ago (or the phones' clocks disagree).
    case outOfDate
    case wrongCode
    /// This exact code was already used for an unlock.
    case alreadyUsed
}

/// Remembers which time-step counters were already redeemed on this phone.
public protocol UsedCounterStore: Sendable {
    func contains(_ counter: Int64) -> Bool
    func insert(_ counter: Int64)
}

public final class DefaultsUsedCounterStore: UsedCounterStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    /// Only recent counters matter: older codes are rejected as out of date anyway.
    private static let limit = 50

    public init(defaults: UserDefaults = .standard, key: String = "qr.usedCounters") {
        self.defaults = defaults
        self.key = key
    }

    private var values: [Int64] { (defaults.array(forKey: key) as? [NSNumber])?.map(\.int64Value) ?? [] }

    public func contains(_ counter: Int64) -> Bool { lock.withLock { values.contains(counter) } }

    public func insert(_ counter: Int64) {
        lock.withLock {
            var next = values
            next.append(counter)
            defaults.set(next.suffix(Self.limit).map { NSNumber(value: $0) }, forKey: key)
        }
    }
}

public final class InMemoryUsedCounterStore: UsedCounterStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: Set<Int64> = []
    public init() {}
    public func contains(_ counter: Int64) -> Bool { lock.withLock { values.contains(counter) } }
    public func insert(_ counter: Int64) { lock.withLock { _ = values.insert(counter) } }
}

/// Verifies a scanned code on the phone, offline, with this phone's copy of the pair secret.
public struct QRUnlockVerifier: Sendable {
    public let secret: QRSecret
    public let used: any UsedCounterStore

    public init(secret: QRSecret, used: any UsedCounterStore) {
        self.secret = secret
        self.used = used
    }

    /// Returns the redeemed counter and marks it used, or says why the code does not work.
    public func redeem(_ scanned: String, at date: Date) -> Result<Int64, QRVerificationError> {
        guard let payload = QRUnlockPayload(scanned) else { return .failure(.unrecognized) }
        guard payload.pairID == secret.pairID else { return .failure(.differentPair) }
        guard abs(payload.counter - TOTP.counter(at: date)) <= TOTP.tolerance else { return .failure(.outOfDate) }
        guard payload.code == TOTP.code(secret: secret.secret, counter: payload.counter) else { return .failure(.wrongCode) }
        guard !used.contains(payload.counter) else { return .failure(.alreadyUsed) }
        used.insert(payload.counter)
        return .success(payload.counter)
    }
}

/// Offline QR unlocks waiting to be sent to the server (`sync_qr_unlocks`).
public final class PendingQRUnlocks: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "qr.pendingUnlocks") {
        self.defaults = defaults
        self.key = key
    }

    public var all: [QRUnlockEvent] {
        lock.withLock { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([QRUnlockEvent].self, from: $0) } ?? [] }
    }

    public func add(_ event: QRUnlockEvent) {
        lock.withLock {
            var events = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([QRUnlockEvent].self, from: $0) } ?? []
            events.append(event)
            defaults.set(try? JSONEncoder().encode(events), forKey: key)
        }
    }

    public func remove(_ sent: [QRUnlockEvent]) {
        lock.withLock {
            let ids = Set(sent.map(\.clientEventID))
            let events = (defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([QRUnlockEvent].self, from: $0) } ?? []).filter { !ids.contains($0.clientEventID) }
            defaults.set(try? JSONEncoder().encode(events), forKey: key)
        }
    }
}
