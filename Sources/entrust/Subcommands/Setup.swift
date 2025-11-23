import ArgumentParser
import Foundation

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Configure JIRA/Linear/Reminders and GitHub credentials"
    )

    @Flag(name: .long, help: "Show current configuration")
    var show: Bool = false

    @Flag(name: .long, help: "Clear stored configuration")
    var clear: Bool = false

    func run() async throws {
        if show {
            try showConfiguration()
            return
        }

        if clear {
            try clearConfiguration()
            print("✅ Configuration cleared")
            return
        }

        print("🔧 Task Automation Setup")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        // Task Tracker Configuration
        print("📋 Task Tracker Configuration")
        let trackerType = readInput("Task tracker type [jira/linear/reminders]: ").lowercased()

        guard trackerType == "jira" || trackerType == "linear" || trackerType == "reminders" else {
            throw AutomationError.invalidTrackerType
        }

        var jiraURL: String?
        var jiraEmail: String?
        var jiraToken: String?
        var linearToken: String?
        var remindersListName: String?

        if trackerType == "jira" {
            jiraURL = readInput("JIRA URL (e.g., https://your-org.atlassian.net): ")
            jiraEmail = readInput("JIRA Email: ")
            jiraToken = readSecureInput("JIRA API Token: ")
        } else if trackerType == "linear" {
            linearToken = readSecureInput("Linear API Token: ")
        } else if trackerType == "reminders" {
            print("\n📱 Reminders Configuration")
            print("   Use Reminders app lists as Kanban columns (e.g., Backlog, In Progress, In Review, Done)")
            remindersListName = readInput("Primary Reminders list name (where tasks are stored): ")
        }

        // GitHub Configuration
        print("\n🐙 GitHub Configuration")
        let useGHCLI = readInput("Use GitHub CLI? (recommended) [y/n]: ").lowercased() == "y"

        var githubToken: String? = nil
        if !useGHCLI {
            githubToken = readSecureInput("GitHub Personal Access Token: ")
        }

        let repo = readInput("Default repository (org/repo): ")
        let baseBranch = readInput("Default base branch [main]: ", default: "main")

        // AI Agent Configuration
        print("\n🤖 AI Agent Configuration")
        print("   Available agents: claude-code, aider, cursor, codex, gemini, copilot")
        let aiAgentType = readInput("AI agent [claude-code]: ", default: "claude-code").lowercased()

        // Additional Settings
        print("\n⚙️  Additional Settings")
        let autoCreateDraft = readInput("Create draft PRs by default? [y/n]: ").lowercased() == "y"
        let runTestsByDefault = readInput("Run tests by default? [y/n]: ", default: "y").lowercased() == "y"

        // Build configuration
        let config = Configuration(
            trackerType: trackerType,
            jiraURL: jiraURL,
            jiraEmail: jiraEmail,
            remindersListName: remindersListName,
            repo: repo,
            baseBranch: baseBranch,
            useGHCLI: useGHCLI,
            autoCreateDraft: autoCreateDraft,
            aiAgentType: aiAgentType,
            runTestsByDefault: runTestsByDefault
        )

        // Save to keychain and config file
        try saveConfiguration(config)

        if let jiraToken = jiraToken {
            try KeychainManager.save(jiraToken, for: .jiraToken)
        }

        if let linearToken = linearToken {
            try KeychainManager.save(linearToken, for: .linearToken)
        }

        if let githubToken = githubToken {
            try KeychainManager.save(githubToken, for: .githubToken)
        }

        print("\n✅ Configuration saved successfully!")
        print("\n💡 Tip: Run 'task-automation setup --show' to view your configuration")
    }

    func readInput(_ prompt: String, default defaultValue: String = "") -> String {
        print(prompt, terminator: "")
        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            return input
        }
        return defaultValue
    }

    func readSecureInput(_ prompt: String) -> String {
        print(prompt, terminator: "")

        var oldt = termios()
        tcgetattr(STDIN_FILENO, &oldt)
        var newt = oldt
        newt.c_lflag &= ~UInt(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &newt)

        defer {
            tcsetattr(STDIN_FILENO, TCSANOW, &oldt)
            print()
        }

        return readLine() ?? ""
    }

    func showConfiguration() throws {
        let config = try ConfigurationManager.load()

        print("📋 Current Configuration")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Task Tracker:       \(config.trackerType.uppercased())")

        if config.trackerType == "jira" {
            print("JIRA URL:           \(config.jiraURL ?? "N/A")")
            print("JIRA Email:         \(config.jiraEmail ?? "N/A")")
        } else if config.trackerType == "reminders" {
            print("Reminders List:     \(config.remindersListName ?? "N/A")")
        }

        print("Repository:         \(config.repo)")
        print("Base Branch:        \(config.baseBranch)")
        print("Use GitHub CLI:     \(config.useGHCLI ? "Yes" : "No")")
        print("Draft PRs:          \(config.autoCreateDraft ? "Yes" : "No")")
        print("Run Tests:          \(config.runTestsByDefault ? "Yes" : "No")")

        print("\n🤖 AI Agent")
        let agentType = AIAgentType(rawValue: config.aiAgentType ?? "claude-code") ?? .claudeCode
        print("Agent:              \(agentType.displayName)")

        print("\n🔐 Stored Credentials")
        if config.trackerType == "jira" {
            print("JIRA Token:         \(KeychainManager.exists(.jiraToken) ? "✓ Stored" : "✗ Missing")")
        } else if config.trackerType == "linear" {
            print("Linear Token:       \(KeychainManager.exists(.linearToken) ? "✓ Stored" : "✗ Missing")")
        } else if config.trackerType == "reminders" {
            print("Reminders:          ✓ Using macOS Reminders (no token needed)")
        }

        if !config.useGHCLI {
            print("GitHub Token:       \(KeychainManager.exists(.githubToken) ? "✓ Stored" : "✗ Missing")")
        }
    }

    func clearConfiguration() throws {
        try ConfigurationManager.clear()
        try? KeychainManager.delete(.jiraToken)
        try? KeychainManager.delete(.linearToken)
        try? KeychainManager.delete(.githubToken)
    }

    func saveConfiguration(_ config: Configuration) throws {
        try ConfigurationManager.save(config)
    }
}
