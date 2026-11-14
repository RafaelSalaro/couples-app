import Core
import Foundation
import Testing
@testable import QRCode

@Suite struct TOTPTests {
    /// RFC 6238 Appendix B test vectors (SHA-1, secret "12345678901234567890"), truncated to 6 digits.
    @Test(arguments: [
        (59, "287082"), (1_111_111_109, "081804"), (1_111_111_111, "050471"),
        (1_234_567_890, "005924"), (2_000_000_000, "279037"), (20_000_000_000, "353130"),
    ])
    func rfc6238Vectors(time: Int, expected: String) {
        let secret = Data("12345678901234567890".utf8)
        #expect(TOTP.code(secret: secret, at: Date(timeIntervalSince1970: TimeInterval(time))) == expected)
    }

    /// RFC 4226 Appendix D HOTP vectors.
    @Test func rfc4226Vectors() {
        let secret = Data("12345678901234567890".utf8)
        let expected = ["755224", "287082", "359152", "969429", "338314", "254676", "287922", "162583", "399871", "520489"]
        #expect((0..<10).map { TOTP.code(secret: secret, counter: Int64($0)) } == expected)
    }

    @Test func codeChangesEveryThirtySeconds() {
        let secret = Data(repeating: 9, count: 20)
        let t = Date(timeIntervalSince1970: 1_800_000_000) // on a step boundary
        #expect(TOTP.counter(at: t) == 60_000_000)
        #expect(TOTP.code(secret: secret, at: t) == TOTP.code(secret: secret, at: t.addingTimeInterval(29.9)))
        #expect(TOTP.code(secret: secret, at: t) != TOTP.code(secret: secret, at: t.addingTimeInterval(30)))
        #expect(TOTP.secondsRemaining(at: t.addingTimeInterval(10)) == 20)
        #expect(abs(TOTP.progress(at: t.addingTimeInterval(15)) - 0.5) < 0.0001)
        #expect(TOTP.code(secret: secret, at: t).count == 6)
    }
}

@Suite struct QRUnlockTests {
    let secret = QRSecret(pairID: UUID(), secret: Data(repeating: 7, count: 20), version: 1)
    let now = Date(timeIntervalSince1970: 1_800_000_010)

    func verifier(_ secret: QRSecret? = nil) -> QRUnlockVerifier {
        QRUnlockVerifier(secret: secret ?? self.secret, used: InMemoryUsedCounterStore())
    }

    @Test func payloadRoundTrip() {
        let payload = QRUnlockPayload(secret: secret, at: now)
        #expect(QRUnlockPayload(payload.string) == payload)
        #expect(payload.string.hasPrefix("couples-unlock:1:"))
        #expect(QRUnlockPayload("https://example.com/i/abc") == nil)
        #expect(QRUnlockPayload("couples-unlock:1:not-a-uuid:1:123456") == nil)
        #expect(QRUnlockPayload("couples-unlock:2:\(secret.pairID.uuidString):1:123456") == nil)
        #expect(QRUnlockPayload("couples-unlock:1:\(secret.pairID.uuidString):1:12345a") == nil)
        // The secret itself is never in the code.
        #expect(!payload.string.contains(secret.secret.base64EncodedString()))
    }

    @Test func validCodeUnlocksOnceOffline() {
        let v = verifier()
        let scanned = QRUnlockPayload(secret: secret, at: now).string
        #expect(v.redeem(scanned, at: now) == .success(TOTP.counter(at: now)))
        // 07 §3: a used code cannot be reused.
        #expect(v.redeem(scanned, at: now) == .failure(.alreadyUsed))
        // The next code works again: being together is unlimited.
        let next = QRUnlockPayload(secret: secret, at: now.addingTimeInterval(30)).string
        #expect(v.redeem(next, at: now.addingTimeInterval(31)) == .success(TOTP.counter(at: now) + 1))
    }

    @Test func oneStepOfClockDriftIsTolerated() {
        let shown = QRUnlockPayload(secret: secret, at: now).string
        #expect(verifier().redeem(shown, at: now.addingTimeInterval(30)) == .success(TOTP.counter(at: now)))
        #expect(verifier().redeem(shown, at: now.addingTimeInterval(-30)) == .success(TOTP.counter(at: now)))
        #expect(verifier().redeem(shown, at: now.addingTimeInterval(60)) == .failure(.outOfDate))
        #expect(verifier().redeem(shown, at: now.addingTimeInterval(-60)) == .failure(.outOfDate))
    }

    @Test func rejections() {
        let v = verifier()
        #expect(v.redeem("hello", at: now) == .failure(.unrecognized))
        let other = QRSecret(pairID: UUID(), secret: secret.secret, version: 1)
        #expect(v.redeem(QRUnlockPayload(secret: other, at: now).string, at: now) == .failure(.differentPair))
        var forged = QRUnlockPayload(secret: secret, at: now)
        forged.code = forged.code == "000000" ? "111111" : "000000"
        #expect(v.redeem(forged.string, at: now) == .failure(.wrongCode))
        // A code made with the old secret stops working after the secret is rotated.
        let rotated = QRSecret(pairID: secret.pairID, secret: Data(repeating: 8, count: 20), version: 2)
        #expect(verifier(rotated).redeem(QRUnlockPayload(secret: secret, at: now).string, at: now) == .failure(.wrongCode))
        // A failed attempt does not burn the counter.
        #expect(v.redeem(QRUnlockPayload(secret: secret, at: now).string, at: now) == .success(TOTP.counter(at: now)))
    }

    @Test func usedCountersAndPendingUnlocksPersist() {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DefaultsUsedCounterStore(defaults: defaults)
        store.insert(42)
        #expect(DefaultsUsedCounterStore(defaults: defaults).contains(42))
        #expect(!store.contains(43))
        for counter in 100..<200 { store.insert(Int64(counter)) }
        #expect(!store.contains(42) && store.contains(199)) // bounded

        let pending = PendingQRUnlocks(defaults: defaults)
        let a = QRUnlockEvent(counter: 1, minutes: 15, startedAt: now), b = QRUnlockEvent(counter: 2, minutes: 30, startedAt: now)
        pending.add(a)
        pending.add(b)
        #expect(PendingQRUnlocks(defaults: defaults).all == [a, b])
        pending.remove([a])
        #expect(pending.all == [b])
    }

    @Test func secretStores() {
        let memory = InMemoryQRSecretStore()
        #expect(memory.load() == nil)
        memory.save(secret)
        #expect(memory.load() == secret)
        memory.save(nil)
        #expect(memory.load() == nil)
    }

    @MainActor @Test func rendersAQRImage() {
        let image = QRImage.make(QRUnlockPayload(secret: secret, at: now).string)
        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 100)
    }
}
