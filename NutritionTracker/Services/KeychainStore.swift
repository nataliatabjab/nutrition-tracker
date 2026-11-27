import Foundation
import Security

/// Small wrapper for keeping secrets such as the Claude API key in the iOS Keychain instead of UserDefaults.
enum KeychainStore {
    private static let service = "com.nataliatabjab.NutritionTracker"

    static func string(for account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ value: String, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

extension KeychainStore {
    static let claudeKeyAccount = "anthropicApiKey"

    static var claudeAPIKey: String {
        get { string(for: claudeKeyAccount).trimmingCharacters(in: .whitespacesAndNewlines) }
        set { save(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: claudeKeyAccount) }
    }
}
