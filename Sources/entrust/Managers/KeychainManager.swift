import Foundation
#if canImport(Security)
import Security
#endif

enum KeychainKey: String {
    case jiraToken = "com.entrust.jira-token"
    case linearToken = "com.entrust.linear-token"
    case githubToken = "com.entrust.github-token"
}

enum KeychainManager {
    static func save(_ value: String, for key: KeychainKey) throws {
        #if canImport(Security)
        try saveToKeychain(value, for: key)
        #else
        try saveToFile(value, for: key)
        #endif
    }

    static func load(_ key: KeychainKey) throws -> String {
        #if canImport(Security)
        return try loadFromKeychain(key)
        #else
        return try loadFromFile(key)
        #endif
    }

    static func delete(_ key: KeychainKey) throws {
        #if canImport(Security)
        try deleteFromKeychain(key)
        #else
        try deleteFromFile(key)
        #endif
    }

    static func exists(_ key: KeychainKey) -> Bool {
        (try? load(key)) != nil
    }

    // MARK: - macOS Keychain Implementation

    #if canImport(Security)
    private static func saveToKeychain(_ value: String, for key: KeychainKey) throws {
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

    private static func loadFromKeychain(_ key: KeychainKey) throws -> String {
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

    private static func deleteFromKeychain(_ key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AutomationError.keychainDeleteFailed(key.rawValue)
        }
    }
    #endif

    // MARK: - Linux File-based Implementation

    private static var credentialsDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".entrust/credentials")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700] // Only owner can read/write/execute
        )

        return dir
    }

    private static func credentialPath(for key: KeychainKey) -> URL {
        credentialsDirectory.appendingPathComponent(key.rawValue)
    }

    private static func saveToFile(_ value: String, for key: KeychainKey) throws {
        let path = credentialPath(for: key)

        try value.write(to: path, atomically: true, encoding: .utf8)

        // Set file permissions to 0600 (only owner can read/write)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path.path
        )
    }

    private static func loadFromFile(_ key: KeychainKey) throws -> String {
        let path = credentialPath(for: key)

        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AutomationError.keychainLoadFailed(key.rawValue)
        }

        return try String(contentsOf: path, encoding: .utf8)
    }

    private static func deleteFromFile(_ key: KeychainKey) throws {
        let path = credentialPath(for: key)

        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
}

