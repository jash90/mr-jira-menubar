import Foundation
import Security

public protocol SecretStore: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String) throws
}

public enum KeychainError: Error, CustomStringConvertible {
    case unexpectedStatus(OSStatus)
    public var description: String {
        switch self {
        case .unexpectedStatus(let s):
            let msg = SecCopyErrorMessageString(s, nil) as String? ?? "OSStatus \(s)"
            return "Błąd Keychain: \(msg)"
        }
    }
}

public final class KeychainSecretStore: SecretStore {
    private let service: String
    public init(service: String = "com.redge.mrjiramenubar") { self.service = service }

    public func string(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?, forKey key: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        guard let value, let data = value.data(using: .utf8) else {
            let status = SecItemDelete(base as CFDictionary)

            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }

            return
        }

        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess { return }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)

        guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
    }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String]
    public init(_ initial: [String: String] = [:]) { storage = initial }

    public func string(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ value: String?, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }
}
