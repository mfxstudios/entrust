import ArgumentParser
import Foundation

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Automate a JIRA or Linear task using Claude Code"
    )

    @Argument(help: "Ticket ID (e.g., IOS-1234 or PRO-123)")
    var ticketID: String

    @Option(name: .long, help: "Override task tracker type [jira/linear]")
    var tracker: String?

    @Option(name: .long, help: "Override JIRA base URL")
    var jiraURL: String?

    @Option(name: .long, help: "Override GitHub repository (org/repo)")
    var repo: String?

    @Option(name: .long, help: "Override base branch for PR")
    var baseBranch: String?

    @Flag(name: .long, help: "Override: Use GitHub CLI instead of API")
    var useGHCLI: Bool = false

    @Flag(name: .long, help: "Override: Skip running tests")
    var skipTests: Bool = false

    @Flag(name: .long, help: "Override: Create draft PR")
    var draft: Bool = false

    @Flag(name: .long, help: "Dry run - show what would be done without executing")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Run Claude Code in a new terminal window")
    var newTerminal: Bool = false

    func run() async throws {
        let config = try ConfigurationManager.load()

        let effectiveTracker = tracker ?? config.trackerType
        let effectiveJiraURL = jiraURL ?? config.jiraURL
        let effectiveRepo = repo ?? config.repo
        let effectiveBaseBranch = baseBranch ?? config.baseBranch
        let effectiveUseGHCLI = useGHCLI || config.useGHCLI
        let effectiveSkipTests = skipTests || !config.runTestsByDefault
        let effectiveDraft = draft || config.autoCreateDraft
        let effectiveNewTerminal = newTerminal || config.useNewTerminal

        // If new terminal is requested, relaunch in new terminal window
        if effectiveNewTerminal {
            try await launchInNewTerminal()
            return
        }

        // Only JIRA and Linear supported
        guard effectiveTracker == "jira" || effectiveTracker == "linear" else {
            print("❌ Only 'jira' and 'linear' trackers are supported")
            throw AutomationError.configurationNotFound
        }

        // Load credentials based on tracker type
        let taskTracker: any TaskTracker

        if effectiveTracker == "jira" {
            guard let jiraURL = effectiveJiraURL, let jiraEmail = config.jiraEmail else {
                throw AutomationError.missingJIRAConfiguration
            }
            let jiraToken = try KeychainManager.load(.jiraToken)
            taskTracker = JIRATracker(url: jiraURL, email: jiraEmail, token: jiraToken)
        } else {
            let linearToken = try KeychainManager.load(.linearToken)
            taskTracker = LinearTracker(token: linearToken)
        }

        let githubToken = effectiveUseGHCLI ? nil : try? KeychainManager.load(.githubToken)

        // Always use Claude Code
        let agent = ClaudeCodeAgent()

        if dryRun {
            print("🧪 DRY RUN MODE")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("Ticket:         \(ticketID)")
            print("Tracker:        \(effectiveTracker.uppercased())")
            print("AI Agent:       Claude Code")
            print("Repository:     \(effectiveRepo)")
            print("Base Branch:    \(effectiveBaseBranch)")
            print("Use GitHub CLI: \(effectiveUseGHCLI)")
            print("Skip Tests:     \(effectiveSkipTests)")
            print("Draft PR:       \(effectiveDraft)")
            print("\n✅ Configuration valid. Run without --dry-run to execute.")
            return
        }

        // Get current repo root
        let repoRoot = try await Shell.run("git", "rev-parse", "--show-toplevel")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Create GitHub service
        let githubConfig = GitHubConfiguration(
            repo: effectiveRepo,
            baseBranch: effectiveBaseBranch,
            useGHCLI: effectiveUseGHCLI,
            token: githubToken,
            draft: effectiveDraft
        )
        let githubService = GitHubService(configuration: githubConfig)

        let automation = TicketAutomation(
            ticketID: ticketID,
            repoRoot: repoRoot,
            taskTracker: taskTracker,
            githubService: githubService,
            aiAgent: agent,
            skipTests: effectiveSkipTests,
            draft: effectiveDraft,
            maxRetryAttempts: config.maxRetryAttempts,
            xcodeScheme: config.xcodeScheme,
            xcodeDestination: config.xcodeDestination
        )

        try await automation.execute()
    }

    /// Launch the command in a new terminal window
    private func launchInNewTerminal() async throws {
        // Build the command to run in the new terminal
        var args: [String] = ["run", ticketID]

        // Add all options except --new-terminal
        if let tracker = tracker {
            args.append(contentsOf: ["--tracker", tracker])
        }
        if let jiraURL = jiraURL {
            args.append(contentsOf: ["--jira-url", jiraURL])
        }
        if let repo = repo {
            args.append(contentsOf: ["--repo", repo])
        }
        if let baseBranch = baseBranch {
            args.append(contentsOf: ["--base-branch", baseBranch])
        }
        if useGHCLI {
            args.append("--use-gh-cli")
        }
        if skipTests {
            args.append("--skip-tests")
        }
        if draft {
            args.append("--draft")
        }
        if dryRun {
            args.append("--dry-run")
        }

        // Get the path to entrust binary
        let entrustPath = ProcessInfo.processInfo.arguments[0]

        // Build the full command
        let command = "\(entrustPath) \(args.joined(separator: " ")); echo ''; echo 'Press Enter to close...'; read"

        // Get current directory
        let workingDirectory = FileManager.default.currentDirectoryPath

        print("🚀 Launching entrust in new terminal window...")
        print("📂 Working directory: \(workingDirectory)")
        print("🎫 Ticket: \(ticketID)")

        // Launch in new terminal
        try await TerminalLauncher.launch(
            command: command,
            workingDirectory: workingDirectory,
            title: "entrust - \(ticketID)"
        )

        print("✅ Entrust is running in a new terminal window")
    }
}
