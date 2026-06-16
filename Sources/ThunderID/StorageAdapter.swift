import Foundation
import Security

/// Interface for custom token/session storage backends (spec §11.1).
public protocol StorageAdapter {
    func store(key: String, value: String) throws
    func retrieve(key: String) -> String?
    func delete(key: String)
    func clear()
}

/// Default storage using iOS Keychain Services (spec §11.1).
public final class KeychainStorageAdapter: StorageAdapter {
    private let service: String

    public init(service: String = "dev.thunderid.sdk") {
        self.service = service
    }

    public func store(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw IAMError(code: .unknownError, message: "Keychain write failed: \(status)")
        }
    }

    public func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    public func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory storage adapter for testing.
public final class InMemoryStorageAdapter: StorageAdapter {
    private var store: [String: String] = [:]

    public init() {}

    public func store(key: String, value: String) { store[key] = value }
    public func retrieve(key: String) -> String? { store[key] }
    public func delete(key: String) { store.removeValue(forKey: key) }
    public func clear() { store.removeAll() }
}
