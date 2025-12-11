import Testing
import Foundation
@testable import entrust

@Suite("ConfigurationManager Tests", .serialized)
final class ConfigurationManagerTests {
    let testDirectory: URL
    let originalDirectory: String

    init() {
        // Save original directory
        originalDirectory = FileManager.default.currentDirectoryPath

        // Create temporary test directory
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("entrust-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        // Change to test directory
        FileManager.default.changeCurrentDirectoryPath(testDirectory.path)
    }

    deinit {
        // Restore original directory
        FileManager.default.changeCurrentDirectoryPath(originalDirectory)

        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)
    }

    @Test("Save and load configuration")
    func saveAndLoadConfiguration() throws {
        // Given
        let config = Configuration(
            trackerType: "jira",
            jiraURL: "https://test.atlassian.net",
            jiraEmail: "test@example.com",
            repo: "testorg/testrepo",
            baseBranch: "main",
            useGHCLI: true,
            autoCreateDraft: false,
            runTestsByDefault: true
        )

        // When
        try ConfigurationManager.save(config)

        // Then - .env file should exist
        let envPath = testDirectory.appendingPathComponent(".env")
        #expect(FileManager.default.fileExists(atPath: envPath.path))

        // Then - should be able to load config back
        let loadedConfig = try ConfigurationManager.load()
        #expect(loadedConfig.trackerType == "jira")
        #expect(loadedConfig.jiraURL == "https://test.atlassian.net")
        #expect(loadedConfig.jiraEmail == "test@example.com")
        #expect(loadedConfig.repo == "testorg/testrepo")
        #expect(loadedConfig.baseBranch == "main")
        #expect(loadedConfig.useGHCLI == true)
        #expect(loadedConfig.autoCreateDraft == false)
        #expect(loadedConfig.runTestsByDefault == true)
    }

    @Test("Configuration not found throws error")
    func configurationNotFoundError() throws {
        // When/Then - loading without setup should throw
        #expect(throws: AutomationError.configurationNotFound) {
            try ConfigurationManager.load()
        }
    }

    @Test("Configuration is project-specific")
    func configurationIsProjectSpecific() throws {
        // Given - save config in first directory
        let config1 = Configuration(
            trackerType: "jira",
            jiraURL: "https://project1.atlassian.net",
            jiraEmail: "project1@example.com",
            repo: "org1/repo1",
            baseBranch: "main",
            useGHCLI: true,
            autoCreateDraft: false,
            runTestsByDefault: true
        )
        try ConfigurationManager.save(config1)

        // When - create second directory
        let testDirectory2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("entrust-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory2, withIntermediateDirectories: true)
        FileManager.default.changeCurrentDirectoryPath(testDirectory2.path)

        // Then - should not find config from first directory
        #expect(throws: (any Error).self) {
            try ConfigurationManager.load()
        }

        // When - save different config in second directory
        let config2 = Configuration(
            trackerType: "linear",
            repo: "org2/repo2",
            baseBranch: "develop",
            useGHCLI: false,
            autoCreateDraft: true,
            runTestsByDefault: false
        )
        try ConfigurationManager.save(config2)

        // Then - should load config2
        let loaded2 = try ConfigurationManager.load()
        #expect(loaded2.trackerType == "linear")
        #expect(loaded2.repo == "org2/repo2")

        // When - switch back to first directory
        FileManager.default.changeCurrentDirectoryPath(testDirectory.path)

        // Then - should load config1
        let loaded1 = try ConfigurationManager.load()
        #expect(loaded1.trackerType == "jira")
        #expect(loaded1.jiraURL == "https://project1.atlassian.net")
        #expect(loaded1.repo == "org1/repo1")

        // Cleanup
        try? FileManager.default.removeItem(at: testDirectory2)
    }

    @Test("Clear configuration removes .env file")
    func clearConfiguration() throws {
        // Given
        let config = Configuration(
            trackerType: "jira",
            jiraURL: "https://test.atlassian.net",
            jiraEmail: "test@example.com",
            repo: "testorg/testrepo",
            baseBranch: "main",
            useGHCLI: true,
            autoCreateDraft: false,
            runTestsByDefault: true
        )
        try ConfigurationManager.save(config)

        // When
        try ConfigurationManager.clear()

        // Then
        #expect(throws: (any Error).self) {
            try ConfigurationManager.load()
        }
    }

    @Test("Configuration file has secure permissions")
    func configurationFilePermissions() throws {
        // Given
        let config = Configuration(
            trackerType: "jira",
            jiraURL: "https://test.atlassian.net",
            jiraEmail: "test@example.com",
            repo: "testorg/testrepo",
            baseBranch: "main",
            useGHCLI: true,
            autoCreateDraft: false,
            runTestsByDefault: true
        )

        // When
        try ConfigurationManager.save(config)

        // Then - check file permissions are 0600 (owner read/write only)
        let envPath = testDirectory.appendingPathComponent(".env")
        let attributes = try FileManager.default.attributesOfItem(atPath: envPath.path)
        let permissions = attributes[.posixPermissions] as! NSNumber
        #expect(permissions.intValue == 0o600)
    }
}
