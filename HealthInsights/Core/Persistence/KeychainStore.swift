import Foundation
import Security

/// Minimal Keychain wrapper for storing small secrets (OAuth client
/// IDs/secrets and tokens) as strings. Values are stored as generic passwords
/// scoped to this app. Access is after-first-unlock so a background refresh can
/// read them.
struct KeychainStore {
    let service: String

    init(service: String = "com.healthinsights.credentials") {
        self.service = service
    }

    @discardableResult
    func set(_ value: String?, for key: String) -> Bool {
        guard let value, !value.isEmpty else { return delete(key) }
        let data = Data(value.utf8)
        var query = baseQuery(key)
        // Upsert: delete then add keeps this simple and atomic enough here.
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func delete(_ key: String) -> Bool {
        SecItemDelete(baseQuery(key) as CFDictionary) == errSecSuccess
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
