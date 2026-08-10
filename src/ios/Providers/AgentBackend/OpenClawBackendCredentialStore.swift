import Foundation
import Security

/// Storage boundary for the OpenClaw Gateway bearer token. The default
/// implementation is the iOS Keychain; tests inject an in-memory stand-in so
/// store semantics are validated without relying on a Keychain entitlement.
protocol OpenClawCredentialStorage: Sendable {
    func save(_ token: String) -> Bool
    func load() -> String?
    func delete()
}

/// Keychain-backed, device-local, non-synchronizable storage for the OpenClaw
/// Gateway owner/operator bearer token, per
/// `docs/security/soulnest-backend-security.md`.
///
/// The token is a backend operator credential, so it deliberately never touches
/// UserDefaults, logs, WebApp/PWA assets, or iCloud Keychain synchronization.
/// Base URL / agent ID remain ordinary app configuration.
struct OpenClawKeychainCredentialStorage: OpenClawCredentialStorage {
    static let keychainService = "com.soulnest.openclaw"
    static let keychainAccount = "gateway-token"

    func save(_ token: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        // Replace/update in place when the item already exists; otherwise add.
        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attrs) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            OpenClawBackendCredentialStore.logKeychainError("save", status)
            return false
        }
        return true
    }

    func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                OpenClawBackendCredentialStore.logKeychainError("load", status)
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            OpenClawBackendCredentialStore.logKeychainError("delete", status)
        }
    }
}

/// App-facing access to the OpenClaw Gateway credential. Keeps the Keychain
/// implementation behind an injectable boundary so the chat-loop path never
/// depends on a concrete storage mechanism and unit tests run deterministically.
///
/// The stored value is only ever read on demand by the OpenClaw adapter;
/// nothing here writes it to UserDefaults and nothing logs its contents.
enum OpenClawBackendCredentialStore {
    /// Tests swap this for an in-memory implementation. App code uses the
    /// Keychain-backed default. Test-only mutation happens serially in
    /// setUp/tearDown; app reads run on the main thread, matching the repo's
    /// pattern for nonisolated test-injectable statics.
    nonisolated(unsafe) static var storage: OpenClawCredentialStorage = OpenClawKeychainCredentialStorage()

    static func save(_ token: String) -> Bool { storage.save(token) }
    static func load() -> String? { storage.load() }
    static func delete() { storage.delete() }
    static var isConfigured: Bool { load() != nil }

    private static let logger = AppLogger(category: "OpenClawBackend")

    /// Logs Keychain operations without ever including the token contents.
    static func logKeychainError(_ operation: String, _ status: OSStatus) {
        logger.error("OpenClaw Gateway credential \(operation) failed status=\(status)")
    }
}
