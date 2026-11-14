import Core
import Foundation
import Security

/// Where this phone keeps the pair's QR secret. The real store is the Keychain (never the App Group).
public protocol QRSecretStore: Sendable {
    func load() -> QRSecret?
    func save(_ secret: QRSecret?)
}

public final class InMemoryQRSecretStore: QRSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secret: QRSecret?
    public init(_ secret: QRSecret? = nil) { self.secret = secret }
    public func load() -> QRSecret? { lock.withLock { secret } }
    public func save(_ secret: QRSecret?) { lock.withLock { self.secret = secret } }
}

/// Keychain storage with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (04 §4).
public final class KeychainQRSecretStore: QRSecretStore, @unchecked Sendable {
    private let service: String
    private let account = "pair-qr-secret"

    public init(service: String = (Bundle.main.bundleIdentifier ?? "couplesapp") + ".qr") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> QRSecret? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(QRSecret.self, from: data)
    }

    public func save(_ secret: QRSecret?) {
        SecItemDelete(query as CFDictionary)
        guard let secret, let data = try? JSONEncoder().encode(secret) else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
