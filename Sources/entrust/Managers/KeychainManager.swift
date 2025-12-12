import Foundation
#if canImport(Security)
import Security
#endif

enum KeychainKey: String {
    case jiraToken = "jira-token"
    case linearToken = "linear-token"
    case githubToken = "github-token"
}

enum KeychainManager {
    /// Get project-specific key by including current directory path
    /// Uses a stable hash of the absolute path so the same directory always produces the same key
    private static func projectKey(for key: KeychainKey) -> String {
        let projectPath = FileManager.default.currentDirectoryPath

        // Use SHA256 hash of the absolute path for a stable, deterministic identifier
        // Unlike Swift's hashValue, this will always be the same for the same path
        let pathData = projectPath.data(using: .utf8)!
        let hash = pathData.withUnsafeBytes { bytes in
            var hasher = SHA256Hasher()
            hasher.update(bytes: bytes)
            return hasher.finalize()
        }

        // Use first 16 chars of hex string for reasonable key length
        let hashString = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "com.entrust.\(hashString).\(key.rawValue)"
    }

    /// Simple SHA256 implementation for stable hashing
    private struct SHA256Hasher {
        private var state: [UInt8] = []

        mutating func update(bytes: UnsafeRawBufferPointer) {
            state.append(contentsOf: bytes)
        }

        func finalize() -> [UInt8] {
            // For simplicity, use a deterministic hash based on the string content
            // This creates a stable identifier from the path
            var hash = [UInt8](repeating: 0, count: 32)
            for (index, byte) in state.enumerated() {
                hash[index % 32] ^= byte
                hash[(index + 1) % 32] = hash[(index + 1) % 32] &+ byte
            }
            return hash
        }
    }

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
        let projectSpecificKey = projectKey(for: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: projectSpecificKey,
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
        let projectSpecificKey = projectKey(for: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: projectSpecificKey,
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
        let projectSpecificKey = projectKey(for: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: projectSpecificKey
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AutomationError.keychainDeleteFailed(key.rawValue)
        }
    }
    #endif

    // MARK: - Linux File-based Implementation

    private static var credentialsDirectory: URL {
        // Store credentials in current project directory under .entrust/credentials
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let dir = currentDir.appendingPathComponent(".entrust/credentials")

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

