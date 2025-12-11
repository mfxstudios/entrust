import Foundation

struct Configuration: Codable {
    // Task Tracker settings
    let trackerType: String  // "jira" or "linear"
    let jiraURL: String?
    let jiraEmail: String?

    // GitHub settings
    let repo: String
    let baseBranch: String
    let useGHCLI: Bool
    let autoCreateDraft: Bool

    // AI Agent settings
    let aiAgentType: String?  // Only "claude-code" is supported

    // Execution settings
    let runTestsByDefault: Bool
    let maxRetryAttempts: Int
    let useNewTerminal: Bool  // Run Claude Code in a new terminal window

    // Xcode-specific settings
    let xcodeScheme: String?
    let xcodeDestination: String?

    // Coding guidelines for custom init with defaults
    init(
        trackerType: String,
        jiraURL: String? = nil,
        jiraEmail: String? = nil,
        repo: String,
        baseBranch: String,
        useGHCLI: Bool,
        autoCreateDraft: Bool,
        aiAgentType: String? = "claude-code",
        runTestsByDefault: Bool,
        maxRetryAttempts: Int = 3,
        useNewTerminal: Bool = false,
        xcodeScheme: String? = nil,
        xcodeDestination: String? = nil
    ) {
        self.trackerType = trackerType
        self.jiraURL = jiraURL
        self.jiraEmail = jiraEmail
        self.repo = repo
        self.baseBranch = baseBranch
        self.useGHCLI = useGHCLI
        self.autoCreateDraft = autoCreateDraft
        self.aiAgentType = aiAgentType
        self.runTestsByDefault = runTestsByDefault
        self.maxRetryAttempts = maxRetryAttempts
        self.useNewTerminal = useNewTerminal
        self.xcodeScheme = xcodeScheme
        self.xcodeDestination = xcodeDestination
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
        // Project-level configuration only - always use .env in current directory
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return currentDir.appendingPathComponent(".env")
    }

    static func save(_ config: Configuration) throws {
        let directory = configPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Convert configuration to .env format
        var lines: [String] = []
        lines.append("# entrust configuration")
        lines.append("# Generated on \(Date())")
        lines.append("")

        lines.append("# Task Tracker Settings")
        lines.append("TRACKER_TYPE=\(config.trackerType)")
        if let jiraURL = config.jiraURL {
            lines.append("JIRA_URL=\(jiraURL)")
        }
        if let jiraEmail = config.jiraEmail {
            lines.append("JIRA_EMAIL=\(jiraEmail)")
        }
        lines.append("")

        lines.append("# GitHub Settings")
        lines.append("GITHUB_REPO=\(config.repo)")
        lines.append("BASE_BRANCH=\(config.baseBranch)")
        lines.append("USE_GH_CLI=\(config.useGHCLI)")
        lines.append("AUTO_CREATE_DRAFT=\(config.autoCreateDraft)")
        lines.append("")

        lines.append("# AI Agent Settings")
        if let aiAgentType = config.aiAgentType {
            lines.append("AI_AGENT_TYPE=\(aiAgentType)")
        }
        lines.append("")

        lines.append("# Execution Settings")
        lines.append("RUN_TESTS_BY_DEFAULT=\(config.runTestsByDefault)")
        lines.append("MAX_RETRY_ATTEMPTS=\(config.maxRetryAttempts)")
        lines.append("USE_NEW_TERMINAL=\(config.useNewTerminal)")
        lines.append("")

        lines.append("# Xcode Settings (optional)")
        if let xcodeScheme = config.xcodeScheme {
            lines.append("XCODE_SCHEME=\(xcodeScheme)")
        }
        if let xcodeDestination = config.xcodeDestination {
            lines.append("XCODE_DESTINATION=\(xcodeDestination)")
        }

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: configPath, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configPath.path
        )
    }

    static func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw AutomationError.configurationNotFound
        }

        let content = try String(contentsOf: configPath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var env: [String: String] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Parse KEY=VALUE
            if let separatorIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<separatorIndex])
                let value = String(trimmed[trimmed.index(after: separatorIndex)...])
                env[key] = value
            }
        }

        // Parse configuration from environment variables
        guard let trackerType = env["TRACKER_TYPE"],
              let repo = env["GITHUB_REPO"],
              let baseBranch = env["BASE_BRANCH"] else {
            throw AutomationError.configurationNotFound
        }

        let useGHCLI = env["USE_GH_CLI"]?.lowercased() == "true"
        let autoCreateDraft = env["AUTO_CREATE_DRAFT"]?.lowercased() == "true"
        let runTestsByDefault = env["RUN_TESTS_BY_DEFAULT"]?.lowercased() == "true"
        let maxRetryAttempts = Int(env["MAX_RETRY_ATTEMPTS"] ?? "3") ?? 3
        let useNewTerminal = env["USE_NEW_TERMINAL"]?.lowercased() == "true"

        return Configuration(
            trackerType: trackerType,
            jiraURL: env["JIRA_URL"],
            jiraEmail: env["JIRA_EMAIL"],
            repo: repo,
            baseBranch: baseBranch,
            useGHCLI: useGHCLI,
            autoCreateDraft: autoCreateDraft,
            aiAgentType: env["AI_AGENT_TYPE"],
            runTestsByDefault: runTestsByDefault,
            maxRetryAttempts: maxRetryAttempts,
            useNewTerminal: useNewTerminal,
            xcodeScheme: env["XCODE_SCHEME"],
            xcodeDestination: env["XCODE_DESTINATION"]
        )
    }

    static func clear() throws {
        try FileManager.default.removeItem(at: configPath)
    }
}


