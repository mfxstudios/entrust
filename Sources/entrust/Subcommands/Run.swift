import ArgumentParser
import Foundation
import ClaudeCodeSDK

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

    @Flag(name: .long, help: "Interactive mode - guide Claude through implementation")
    var interactive: Bool = false

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

        // Handle interactive mode
        if interactive {
            try await runInteractive(
                taskTracker: taskTracker,
                githubService: githubService,
                repoRoot: repoRoot,
                config: config,
                effectiveSkipTests: effectiveSkipTests,
                effectiveDraft: effectiveDraft
            )
            return
        }

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

    /// Run in interactive mode - guide Claude through implementation, then auto-complete
    private func runInteractive(
        taskTracker: any TaskTracker,
        githubService: GitHubService,
        repoRoot: String,
        config: Configuration,
        effectiveSkipTests: Bool,
        effectiveDraft: Bool
    ) async throws {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎯 Interactive Mode - \(ticketID)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("")

        // Fetch task details
        print("📋 Fetching task details...")
        let issue = try await taskTracker.fetchIssue(ticketID)

        print("✅ Task: \(issue.title)")
        print("")

        if let description = issue.description, !description.isEmpty {
            print("Description:")
            print(description)
            print("")
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("💬 Starting Interactive Session")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("")
        print("Commands:")
        print("  • Type your messages to guide Claude")
        print("  • Type 'done' or 'finish' to end and proceed to automation")
        print("  • Type 'cancel' to exit without automation")
        print("")

        // Update ticket status to In Progress
        _ = try? await taskTracker.changeStatus(ticketID, to: "In Progress")

        // Create initial prompt
        let variables = PromptVariables(from: issue, additionalContext: nil)
        let template = DefaultPromptTemplate()
        let initialPrompt = template.render(with: variables)

        // Configure Claude Code client
        var claudeConfig = ClaudeCodeConfiguration.default
        claudeConfig.workingDirectory = repoRoot

        // Auto-detect best backend
        let detector = BackendDetector(configuration: claudeConfig)
        claudeConfig.backend = detector.detect().recommendedBackend

        let client = try ClaudeCodeClient(configuration: claudeConfig)

        // Create interactive session
        let session = try client.createInteractiveSession(
            systemPrompt: """
            You are helping implement a software task. Work iteratively with the user to implement the changes.
            When you make changes, ensure they compile and follow best practices.
            """
        )

        // Start with initial task prompt
        print("🤖 Claude:")
        print("")

        var sessionId: String?

        do {
            for try await event in session.send(initialPrompt) {
                switch event {
                case .text(let chunk):
                    print(chunk, terminator: "")
                    fflush(stdout)

                case .toolUse(let tool):
                    print("\n🔧 Using tool: \(tool.name)")

                case .sessionStarted(let info):
                    sessionId = info.sessionId

                case .completed(let result):
                    sessionId = result.sessionId
                    print("\n")

                case .error(let error):
                    print("\n❌ Error: \(error)")

                default:
                    break
                }
            }
        } catch {
            print("\n❌ Session error: \(error)")
            throw error
        }

        // Interactive loop
        var shouldContinueAutomation = true

        while session.isActive {
            print("")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("You: ", terminator: "")

            guard let userInput = readLine() else {
                break
            }

            let trimmed = userInput.trimmingCharacters(in: .whitespaces)

            // Check for exit commands
            if trimmed.lowercased() == "done" || trimmed.lowercased() == "finish" {
                print("")
                print("✅ Interactive session complete!")
                break
            }

            if trimmed.lowercased() == "cancel" || trimmed.lowercased() == "exit" {
                print("")
                print("🚫 Cancelled - skipping automation")
                shouldContinueAutomation = false
                break
            }

            if trimmed.isEmpty {
                continue
            }

            // Send message and stream response
            print("")
            print("🤖 Claude:")
            print("")

            do {
                for try await event in session.send(trimmed) {
                    switch event {
                    case .text(let chunk):
                        print(chunk, terminator: "")
                        fflush(stdout)

                    case .toolUse(let tool):
                        print("\n🔧 Using tool: \(tool.name)")

                    case .completed(let result):
                        sessionId = result.sessionId
                        print("\n")

                    case .error(let error):
                        print("\n❌ Error: \(error)")

                    default:
                        break
                    }
                }
            } catch {
                print("\n❌ Error: \(error)")
            }
        }

        await session.end()

        // Exit if cancelled
        if !shouldContinueAutomation {
            print("")
            print("👋 Session ended")
            return
        }

        // Continue with automation
        print("")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🤖 Starting Automation Flow")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("")

        // Run tests if not skipped
        if !effectiveSkipTests {
            print("🧪 Running tests...")

            do {
                if let xcodeScheme = config.xcodeScheme {
                    // Xcode project test
                    let testCommand = "xcodebuild test -scheme \(xcodeScheme) -destination '\(config.xcodeDestination ?? "platform=iOS Simulator,name=iPhone 15")'"
                    try await Shell.run(["/bin/bash", "-c", testCommand], workingDirectory: repoRoot)
                } else {
                    // Swift package test
                    try await Shell.run(["swift", "test"], workingDirectory: repoRoot)
                }
                print("✅ Tests passed")
            } catch {
                print("❌ Tests failed:")
                print(error.localizedDescription)
                throw AutomationError.testsFailed
            }
        }

        // Create branch and commit
        let branchName = "feature/\(ticketID.sanitizedForBranchName())"

        print("🌿 Creating branch: \(branchName)")
        try await Shell.run("git", "checkout", "-b", branchName)

        print("💾 Committing changes...")
        try await Shell.run("git", "add", ".")

        let commitMessage = """
        [\(ticketID)] \(issue.title)

        🤖 Implemented via Interactive Mode with Claude Code

        Co-Authored-By: Claude <noreply@anthropic.com>
        """

        try await Shell.run("git", "commit", "-m", commitMessage)

        print("⬆️  Pushing to remote...")
        try await Shell.run("git", "push", "-u", "origin", branchName)

        // Create PR
        print("📬 Creating pull request...")

        let prBody = """
        ## Task
        \(issue.title)

        ## Description
        \(issue.description ?? "No description provided")

        ## Implementation Notes
        This was implemented using Interactive Mode, where changes were guided through conversation with Claude Code.

        ## Session Info
        - Session ID: \(sessionId ?? "unknown")
        - Ticket: \(ticketID)

        🤖 Implemented with [Claude Code](https://claude.com/claude-code) Interactive Mode
        """

        let prParams = PullRequestParams(
            title: "[\(ticketID)] \(issue.title)",
            body: prBody,
            branch: branchName,
            baseBranch: githubService.configuration.baseBranch,
            draft: effectiveDraft
        )

        let prResult = try await githubService.createPullRequest(prParams)

        print("✅ Pull request created: \(prResult.url)")

        // Update ticket status
        _ = try? await taskTracker.updateIssue(ticketID, prURL: prResult.url)
        _ = try? await taskTracker.changeStatus(ticketID, to: "In Review")

        print("")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ Complete!")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("")
        print("📝 Summary:")
        print("  • Interactive session completed")
        print("  • Tests: \(effectiveSkipTests ? "Skipped" : "Passed")")
        print("  • Branch: \(branchName)")
        print("  • PR: \(prResult.url)")
        print("")
    }
}
