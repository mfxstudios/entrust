//
//  Configuration.swift
//  entrust
//
//  Created by Prince Ugwuh on 11/22/25.
//

import Foundation

struct Configuration: Codable {
    // Task Tracker settings
    let trackerType: String  // "jira", "linear", or "reminders"
    let jiraURL: String?
    let jiraEmail: String?
    let remindersListName: String?  // For Reminders tracker

    // GitHub settings
    let repo: String
    let baseBranch: String
    let useGHCLI: Bool
    let autoCreateDraft: Bool

    // AI Agent settings
    let aiAgentType: String?  // "claude-code", "aider", "cursor", "codex", "gemini", "copilot"

    // Execution settings
    let runTestsByDefault: Bool

    // Coding guidelines for custom init with defaults
    init(
        trackerType: String,
        jiraURL: String? = nil,
        jiraEmail: String? = nil,
        remindersListName: String? = nil,
        repo: String,
        baseBranch: String,
        useGHCLI: Bool,
        autoCreateDraft: Bool,
        aiAgentType: String? = "claude-code",
        runTestsByDefault: Bool
    ) {
        self.trackerType = trackerType
        self.jiraURL = jiraURL
        self.jiraEmail = jiraEmail
        self.remindersListName = remindersListName
        self.repo = repo
        self.baseBranch = baseBranch
        self.useGHCLI = useGHCLI
        self.autoCreateDraft = autoCreateDraft
        self.aiAgentType = aiAgentType
        self.runTestsByDefault = runTestsByDefault
    }

    /// Get the configured AI agent
    func getAIAgent() -> any AIAgent {
        let agentType = AIAgentType(rawValue: aiAgentType ?? "claude-code") ?? .claudeCode
        return AIAgentFactory.create(type: agentType)
    }

    /// Get GitHub configuration
    func getGitHubConfiguration(token: String?, draft: Bool? = nil) -> GitHubConfiguration {
        GitHubConfiguration(
            repo: repo,
            baseBranch: baseBranch,
            useGHCLI: useGHCLI,
            token: token,
            draft: draft ?? autoCreateDraft
        )
    }
}

enum ConfigurationManager {
    static var configPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".task-automation")
            .appendingPathComponent("config.json")
    }

    static func save(_ config: Configuration) throws {
        let directory = configPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(config)
        try data.write(to: configPath)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configPath.path
        )
    }

    static func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw AutomationError.configurationNotFound
        }

        let data = try Data(contentsOf: configPath)
        return try JSONDecoder().decode(Configuration.self, from: data)
    }

    static func clear() throws {
        try FileManager.default.removeItem(at: configPath)
    }
}


