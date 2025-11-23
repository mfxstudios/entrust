//
//  KeychainKey.swift
//  entrust
//
//  Created by Prince Ugwuh on 11/22/25.
//

import Foundation

enum KeychainKey: String {
    case jiraToken = "com.task-automation.jira-token"
    case linearToken = "com.task-automation.linear-token"
    case githubToken = "com.task-automation.github-token"
}

enum KeychainManager {
    static func save(_ value: String, for key: KeychainKey) throws {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw AutomationError.keychainSaveFailed(key.rawValue)
        }
    }

    static func load(_ key: KeychainKey) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw AutomationError.keychainLoadFailed(key.rawValue)
        }

        return value
    }

    static func delete(_ key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AutomationError.keychainDeleteFailed(key.rawValue)
        }
    }

    static func exists(_ key: KeychainKey) -> Bool {
        (try? load(key)) != nil
    }
}
