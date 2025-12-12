import Testing
import Foundation
@testable import entrust

@Suite("KeychainManager Tests", .serialized)
final class KeychainManagerTests {
    let testDirectory: URL
    let originalDirectory: String

    init() {
        // Save original directory
        originalDirectory = FileManager.default.currentDirectoryPath

        // Create temporary test directory
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("entrust-keychain-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        // Change to test directory
        FileManager.default.changeCurrentDirectoryPath(testDirectory.path)

        // Clean up any existing credentials from previous test runs
        try? KeychainManager.delete(.jiraToken)
        try? KeychainManager.delete(.linearToken)
        try? KeychainManager.delete(.githubToken)
    }

    deinit {
        // Clean up any saved credentials
        try? KeychainManager.delete(.jiraToken)
        try? KeychainManager.delete(.linearToken)
        try? KeychainManager.delete(.githubToken)

        // Restore original directory
        FileManager.default.changeCurrentDirectoryPath(originalDirectory)

        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)
    }

    @Test("Save and load token")
    func saveAndLoadToken() throws {
        // Given
        let testToken = "test-jira-token-12345"

        // When
        try KeychainManager.save(testToken, for: .jiraToken)

        // Then
        let loadedToken = try KeychainManager.load(.jiraToken)
        #expect(loadedToken == testToken)
    }

    @Test("Load non-existent token throws error")
    func loadNonExistentToken() {
        // When/Then
        #expect(throws: (any Error).self) {
            try KeychainManager.load(.jiraToken)
        }
    }

    @Test("Delete token removes it from storage")
    func deleteToken() throws {
        // Given
        let testToken = "test-token"
        try KeychainManager.save(testToken, for: .linearToken)

        // When
        try KeychainManager.delete(.linearToken)

        // Then
        #expect(throws: (any Error).self) {
            try KeychainManager.load(.linearToken)
        }
    }

    @Test("Exists returns correct status")
    func exists() throws {
        // Given
        #expect(KeychainManager.exists(.githubToken) == false)

        // When
        try KeychainManager.save("test-token", for: .githubToken)

        // Then
        #expect(KeychainManager.exists(.githubToken) == true)
    }

    @Test("Overwrite existing token updates the value")
    func overwriteExistingToken() throws {
        // Given
        let firstToken = "first-token"
        let secondToken = "second-token"

        try KeychainManager.save(firstToken, for: .jiraToken)

        // When - save again with different value
        try KeychainManager.save(secondToken, for: .jiraToken)

        // Then - should have the new value
        let loadedToken = try KeychainManager.load(.jiraToken)
        #expect(loadedToken == secondToken)
    }

    @Test("Tokens are project-specific")
    func projectSpecificKeys() throws {
        // Given - save token in first directory
        let token1 = "project1-token"
        try KeychainManager.save(token1, for: .jiraToken)

        // When - create and switch to second directory
        let testDirectory2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("entrust-keychain-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory2, withIntermediateDirectories: true)
        FileManager.default.changeCurrentDirectoryPath(testDirectory2.path)

        // Then - should not find token from first project
        #expect(KeychainManager.exists(.jiraToken) == false)

        // When - save different token in second directory
        let token2 = "project2-token"
        try KeychainManager.save(token2, for: .jiraToken)

        // Then - should load token2
        let loaded2 = try KeychainManager.load(.jiraToken)
        #expect(loaded2 == token2)

        // When - switch back to first directory
        FileManager.default.changeCurrentDirectoryPath(testDirectory.path)

        // Then - should still have token1
        let loaded1 = try KeychainManager.load(.jiraToken)
        #expect(loaded1 == token1)

        // Cleanup
        FileManager.default.changeCurrentDirectoryPath(testDirectory2.path)
        try? KeychainManager.delete(.jiraToken)
        try? FileManager.default.removeItem(at: testDirectory2)
    }

    @Test("Multiple token types can coexist")
    func multipleTokenTypes() throws {
        // Given
        let jiraToken = "jira-token-123"
        let linearToken = "linear-token-456"
        let githubToken = "github-token-789"

        // When
        try KeychainManager.save(jiraToken, for: .jiraToken)
        try KeychainManager.save(linearToken, for: .linearToken)
        try KeychainManager.save(githubToken, for: .githubToken)

        // Then
        #expect(try KeychainManager.load(.jiraToken) == jiraToken)
        #expect(try KeychainManager.load(.linearToken) == linearToken)
        #expect(try KeychainManager.load(.githubToken) == githubToken)
    }

    #if !canImport(Security)
    @Test("Linux file-based storage has secure permissions")
    func linuxFileBasedStorage() throws {
        // Given
        let testToken = "linux-test-token"

        // When
        try KeychainManager.save(testToken, for: .jiraToken)

        // Then - file should exist with correct permissions
        let credentialsPath = testDirectory
            .appendingPathComponent(".entrust/credentials/jira-token")

        #expect(FileManager.default.fileExists(atPath: credentialsPath.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: credentialsPath.path)
        let permissions = attributes[.posixPermissions] as! NSNumber
        #expect(permissions.intValue == 0o600)
    }
    #endif
}
