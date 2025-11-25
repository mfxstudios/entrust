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

    func run() async throws {
        let config = try ConfigurationManager.load()

        let effectiveTracker = tracker ?? config.trackerType
        let effectiveJiraURL = jiraURL ?? config.jiraURL
        let effectiveRepo = repo ?? config.repo
        let effectiveBaseBranch = baseBranch ?? config.baseBranch
        let effectiveUseGHCLI = useGHCLI || config.useGHCLI
        let effectiveSkipTests = skipTests || !config.runTestsByDefault
        let effectiveDraft = draft || config.autoCreateDraft

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
            taskTracker: taskTracker,
            githubService: githubService,
            aiAgent: agent,
            skipTests: effectiveSkipTests,
            draft: effectiveDraft
        )

        try await automation.execute()
    }
}
