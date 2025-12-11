import ArgumentParser
import Foundation

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Configure JIRA/Linear and GitHub credentials"
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
        let trackerType = readInput("Task tracker type [jira/linear]: ").lowercased()

        guard trackerType == "jira" || trackerType == "linear" else {
            throw AutomationError.invalidTrackerType
        }

        var jiraURL: String?
        var jiraEmail: String?
        var jiraToken: String?
        var linearToken: String?

        if trackerType == "jira" {
            jiraURL = readInput("JIRA URL (e.g., https://your-org.atlassian.net): ", required: true)
            jiraEmail = readInput("JIRA Email: ", required: true)
            jiraToken = readSecureInput("JIRA API Token: ")
        } else if trackerType == "linear" {
            linearToken = readSecureInput("Linear API Token: ")
        }

        // GitHub Configuration
        print("\n🐙 GitHub Configuration")
        let useGHCLI = readInput("Use GitHub CLI? (recommended) [y/n]: ").lowercased() == "y"

        var githubToken: String? = nil
        if !useGHCLI {
            githubToken = readSecureInput("GitHub Personal Access Token: ")
        }

        // Auto-detect repository from git remote
        let detectedRepo = detectGitHubRepo()
        let repoPrompt: String
        let repoDefault: String
        if let detected = detectedRepo {
            repoPrompt = "Default repository (org/repo) [\(detected)]: "
            repoDefault = detected
        } else {
            repoPrompt = "Default repository (org/repo): "
            repoDefault = ""
        }

        let repo = readInput(repoPrompt, default: repoDefault, required: true)
        let baseBranch = readInput("Default base branch [main]: ", default: "main")

        // AI Agent Configuration
        print("\n🤖 AI Agent Configuration")
        print("   Only Claude Code is supported")
        let aiAgentType = "claude-code"

        // Additional Settings
        print("\n⚙️  Additional Settings")
        let autoCreateDraft = readInput("Create draft PRs by default? [y/n]: ").lowercased() == "y"
        let runTestsByDefault = readInput("Run tests by default? [y/n]: ", default: "y").lowercased() == "y"

        // Xcode Settings (optional)
        print("\n🏗️  Xcode Settings (optional - leave blank if not using Xcode)")
        let xcodeSchemeInput = readInput("Xcode scheme name (for running tests): ", default: "")
        let xcodeScheme = xcodeSchemeInput.isEmpty ? nil : xcodeSchemeInput

        let xcodeDestinationInput = readInput("Xcode test destination [platform=iOS Simulator,name=iPhone 15]: ", default: "platform=iOS Simulator,name=iPhone 15")
        let xcodeDestination = (xcodeScheme != nil && !xcodeDestinationInput.isEmpty) ? xcodeDestinationInput : nil

        // Build configuration
        let config = Configuration(
            trackerType: trackerType,
            jiraURL: jiraURL,
            jiraEmail: jiraEmail,
            repo: repo,
            baseBranch: baseBranch,
            useGHCLI: useGHCLI,
            autoCreateDraft: autoCreateDraft,
            aiAgentType: aiAgentType,
            runTestsByDefault: runTestsByDefault,
            xcodeScheme: xcodeScheme,
            xcodeDestination: xcodeDestination
        )

        // Save to keychain and config file
        print("\n💾 Saving configuration...")
        try saveConfiguration(config)
        print("   ✓ Configuration file saved to: \(FileManager.default.currentDirectoryPath)/.env")

        if let jiraToken = jiraToken {
            try KeychainManager.save(jiraToken, for: .jiraToken)
            print("   ✓ JIRA token saved to keychain")
        }

        if let linearToken = linearToken {
            try KeychainManager.save(linearToken, for: .linearToken)
            print("   ✓ Linear token saved to keychain")
        }

        if let githubToken = githubToken {
            try KeychainManager.save(githubToken, for: .githubToken)
            print("   ✓ GitHub token saved to keychain")
        }

        print("\n✅ Configuration saved successfully!")
        print("📂 Working directory: \(FileManager.default.currentDirectoryPath)")
        print("\n💡 Tip: Run 'entrust setup --show' to view your configuration")
        print("⚠️  Remember to add .env and .entrust/ to your .gitignore")
    }

    func readInput(_ prompt: String, default defaultValue: String = "", required: Bool = false) -> String {
        while true {
            print(prompt, terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
                return input
            }

            // If empty and has default, return default
            if !defaultValue.isEmpty {
                return defaultValue
            }

            // If empty and not required, return empty
            if !required {
                return ""
            }

            // If empty but required, prompt again
            print("❌ This field is required. Please enter a value.")
        }
    }

    func readSecureInput(_ prompt: String, allowEmpty: Bool = false) -> String {
        while true {
            print(prompt, terminator: "")

            var oldt = termios()
            tcgetattr(STDIN_FILENO, &oldt)
            var newt = oldt
            newt.c_lflag &= ~UInt(ECHO)
            tcsetattr(STDIN_FILENO, TCSANOW, &newt)

            let input = readLine() ?? ""

            // Restore terminal settings
            tcsetattr(STDIN_FILENO, TCSANOW, &oldt)
            print()

            if !input.isEmpty || allowEmpty {
                return input
            }

            // Token was empty, prompt again
            print("❌ Token cannot be empty. Please enter a valid token.")
        }
    }

    func showConfiguration() throws {
        let config = try ConfigurationManager.load()

        print("📋 Current Configuration")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Task Tracker:       \(config.trackerType.uppercased())")

        if config.trackerType == "jira" {
            print("JIRA URL:           \(config.jiraURL ?? "N/A")")
            print("JIRA Email:         \(config.jiraEmail ?? "N/A")")
        }

        print("Repository:         \(config.repo)")
        print("Base Branch:        \(config.baseBranch)")
        print("Use GitHub CLI:     \(config.useGHCLI ? "Yes" : "No")")
        print("Draft PRs:          \(config.autoCreateDraft ? "Yes" : "No")")
        print("Run Tests:          \(config.runTestsByDefault ? "Yes" : "No")")

        if let xcodeScheme = config.xcodeScheme {
            print("\n🏗️  Xcode Settings")
            print("Scheme:             \(xcodeScheme)")
            if let xcodeDestination = config.xcodeDestination {
                print("Destination:        \(xcodeDestination)")
            }
        }

        print("\n🤖 AI Agent")
        print("Agent:              Claude Code")

        print("\n🔐 Stored Credentials")
        if config.trackerType == "jira" {
            print("JIRA Token:         \(KeychainManager.exists(.jiraToken) ? "✓ Stored" : "✗ Missing")")
        } else if config.trackerType == "linear" {
            print("Linear Token:       \(KeychainManager.exists(.linearToken) ? "✓ Stored" : "✗ Missing")")
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

    /// Auto-detect GitHub org/repo from current git repository
    func detectGitHubRepo() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "config", "--get", "remote.origin.url"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let remoteURL = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !remoteURL.isEmpty else {
                return nil
            }

            // Parse the URL to extract org/repo
            return parseGitHubURL(remoteURL)
        } catch {
            return nil
        }
    }

    /// Parse GitHub URL to extract org/repo
    /// Supports both HTTPS and SSH formats:
    /// - https://github.com/org/repo.git
    /// - git@github.com:org/repo.git
    func parseGitHubURL(_ url: String) -> String? {
        // Remove .git suffix if present
        let cleanURL = url.hasSuffix(".git") ? String(url.dropLast(4)) : url

        // HTTPS format: https://github.com/org/repo
        if cleanURL.contains("https://github.com/") {
            let components = cleanURL.components(separatedBy: "https://github.com/")
            if components.count > 1 {
                return components[1]
            }
        }

        // SSH format: git@github.com:org/repo
        if cleanURL.contains("git@github.com:") {
            let components = cleanURL.components(separatedBy: "git@github.com:")
            if components.count > 1 {
                return components[1]
            }
        }

        return nil
    }
}
