import ArgumentParser
import Foundation

struct Parallel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run automation for multiple tickets in parallel using git worktrees"
    )

    @Argument(help: "Ticket IDs to process (e.g., IOS-1234 IOS-1235)")
    var ticketIDs: [String] = []

    @Option(name: .long, help: "Read ticket IDs from file (one per line)")
    var file: String?

    @Option(name: .long, help: "Maximum concurrent tasks")
    var maxConcurrent: Int = 3

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

    @Flag(name: .long, help: "Dry run - show execution plan without running")
    var dryRun: Bool = false

    func run() async throws {
        let config = try ConfigurationManager.load()

        // Collect all ticket IDs
        var allTickets = ticketIDs
        if let file = file {
            let fileContent = try String(contentsOfFile: file, encoding: .utf8)
            let fileTickets = fileContent.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            allTickets.append(contentsOf: fileTickets)
        }

        guard !allTickets.isEmpty else {
            print("❌ No tickets provided. Use: entrust parallel TASK-1 TASK-2 or --file tasks.txt")
            throw AutomationError.configurationNotFound
        }

        // Remove duplicates while preserving order
        allTickets = Array(NSOrderedSet(array: allTickets)) as! [String]

        print("🎫 Processing \(allTickets.count) ticket(s) with max \(maxConcurrent) concurrent")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

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

        // Setup task tracker
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
        let aiAgent = ClaudeCodeAgent()

        // Create GitHub service configuration
        let githubConfig = GitHubConfiguration(
            repo: effectiveRepo,
            baseBranch: effectiveBaseBranch,
            useGHCLI: effectiveUseGHCLI,
            token: githubToken,
            draft: effectiveDraft
        )

        if dryRun {
            print("🧪 DRY RUN MODE\n")
            print("Tracker:        \(effectiveTracker.uppercased())")
            print("AI Agent:       Claude Code")
            print("Repository:     \(effectiveRepo)")
            print("Base Branch:    \(effectiveBaseBranch)")
            print("Max Concurrent: \(maxConcurrent)\n")
            for (index, ticket) in allTickets.enumerated() {
                print("[\(index + 1)/\(allTickets.count)] \(ticket)")
            }
            print("\n✅ Would process these tickets. Run without --dry-run to execute.")
            return
        }

        // Get current repo root
        let repoRoot = try await Shell.run("git", "rev-parse", "--show-toplevel")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Create parallel executor
        let executor = ParallelExecutor(
            tickets: allTickets,
            repoRoot: repoRoot,
            taskTracker: taskTracker,
            githubConfig: githubConfig,
            aiAgent: aiAgent,
            skipTests: effectiveSkipTests,
            maxConcurrent: maxConcurrent
        )

        try await executor.execute()
    }
}

// MARK: - Parallel Executor

actor ParallelExecutor {
    let tickets: [String]
    let repoRoot: String
    nonisolated let taskTracker: any TaskTracker
    let githubConfig: GitHubConfiguration
    nonisolated let aiAgent: any AIAgent
    let skipTests: Bool
    let maxConcurrent: Int

    private var results: [String: TaskResult] = [:]
    private var worktrees: [String] = []

    init(
        tickets: [String],
        repoRoot: String,
        taskTracker: any TaskTracker,
        githubConfig: GitHubConfiguration,
        aiAgent: any AIAgent,
        skipTests: Bool,
        maxConcurrent: Int
    ) {
        self.tickets = tickets
        self.repoRoot = repoRoot
        self.taskTracker = taskTracker
        self.githubConfig = githubConfig
        self.aiAgent = aiAgent
        self.skipTests = skipTests
        self.maxConcurrent = maxConcurrent
    }

    func execute() async throws {
        let allTickets = tickets
        let totalCount = tickets.count
        let maxConcurrentLimit = maxConcurrent

        // Process tickets with concurrency limit
        await withTaskGroup(of: (String, TaskResult).self) { group in
            var activeCount = 0
            var ticketIndex = 0

            while ticketIndex < allTickets.count || activeCount > 0 {
                // Start new tasks up to max concurrent
                while activeCount < maxConcurrentLimit && ticketIndex < allTickets.count {
                    let ticket = allTickets[ticketIndex]
                    let currentIndex = ticketIndex + 1
                    ticketIndex += 1
                    activeCount += 1

                    group.addTask { [self] in
                        let result = await self.processTicket(
                            ticket,
                            index: currentIndex,
                            total: totalCount
                        )
                        return (ticket, result)
                    }
                }

                // Wait for at least one task to complete
                if let (ticket, result) = await group.next() {
                    activeCount -= 1
                    recordResult(ticket: ticket, result: result)
                }
            }
        }

        // Print summary
        printSummary()
    }

    func processTicket(_ ticketID: String, index: Int, total: Int) async -> TaskResult {
        let startTime = Date()

        print("\n[\(index)/\(total)] 🎫 Processing \(ticketID)...")

        do {
            // Create worktree
            let worktreePath = try await createWorktree(for: ticketID)
            recordWorktree(worktreePath)

            // Fetch issue details
            print("[\(ticketID)] 📋 Fetching issue details...")
            let issue = try await taskTracker.fetchIssue(ticketID)

            // Change status to "In Progress"
            print("[\(ticketID)] 🔄 Moving to 'In Progress'...")
            do {
                try await taskTracker.changeStatus(ticketID, to: "In Progress")
            } catch AutomationError.invalidStatus(let requested, let available) {
                print("[\(ticketID)] ⚠️  Warning: Could not move to '\(requested)'. Available: \(available.joined(separator: ", "))")
            } catch {
                print("[\(ticketID)] ⚠️  Warning: Could not change status: \(error.localizedDescription)")
            }

            // Run Claude Code in worktree
            print("[\(ticketID)] 🤖 Running Claude Code in worktree...")
            let prompt = buildPrompt(for: issue)
            let githubService = GitHubService(configuration: githubConfig)
            let sanitizedTicketID = ticketID.sanitizedForBranchName()
            let branch = "feature/\(sanitizedTicketID)"

            var agentResult = try await aiAgent.execute(
                prompt: prompt,
                context: AIAgentContext(workingDirectory: worktreePath)
            )

            // Run tests with automatic retry on failure
            if !skipTests {
                print("[\(ticketID)] 🧪 Running tests in worktree...")

                do {
                    try await runTests(in: worktreePath)
                } catch {
                    // Tests failed - try to fix automatically using multi-turn
                    if let sessionId = agentResult.sessionId {
                        print("[\(ticketID)] ⚠️  Tests failed: \(error.localizedDescription)")
                        print("[\(ticketID)] 🔄 Asking Claude to fix the test failures...")

                        let fixPrompt = """
                        The tests failed with the following error:
                        \(error.localizedDescription)

                        Please fix the code to make the tests pass. Review what you implemented and correct any issues.
                        """

                        agentResult = try await aiAgent.continueConversation(
                            sessionId: sessionId,
                            prompt: fixPrompt,
                            context: AIAgentContext(workingDirectory: worktreePath)
                        )

                        // Try tests again after fix
                        print("[\(ticketID)] 🧪 Running tests again after fixes...")
                        try await runTests(in: worktreePath)
                        print("[\(ticketID)] ✅ Tests passed after automatic fix!")
                    } else {
                        // No session ID, can't continue conversation
                        print("[\(ticketID)] ❌ Tests failed and cannot auto-fix (no session ID)")
                        throw error
                    }
                }
            }

            // Commit and push using GitHub service
            print("[\(ticketID)] 📤 Committing and pushing...")
            let hasChanges = try await githubService.commitAndPush(
                message: "[\(ticketID)] \(issue.title)",
                branch: branch,
                in: worktreePath
            )

            guard hasChanges else {
                print("[\(ticketID)] ⚠️  No changes were made. Skipping PR creation.")
                let duration = Date().timeIntervalSince(startTime)
                return .failure(error: AutomationError.shellCommandFailed("No changes to commit"), duration: duration)
            }

            // Create PR
            print("[\(ticketID)] 📬 Creating pull request...")
            let prResult = try await githubService.createPullRequest(
                PullRequestParams(
                    title: "[\(ticketID)] \(issue.title)",
                    body: buildPRBody(issue: issue, agentOutput: agentResult.output),
                    branch: branch,
                    baseBranch: githubConfig.baseBranch,
                    draft: githubConfig.draft
                )
            )

            // Update issue
            print("[\(ticketID)] ✅ Updating issue...")
            try await taskTracker.updateIssue(ticketID, prURL: prResult.url)

            // Change status to "In Review"
            print("[\(ticketID)] 🔄 Moving to 'In Review'...")
            do {
                try await taskTracker.changeStatus(ticketID, to: "In Review")
            } catch AutomationError.invalidStatus(let requested, let available) {
                print("[\(ticketID)] ⚠️  Warning: Could not move to '\(requested)'. Available: \(available.joined(separator: ", "))")
            } catch {
                print("[\(ticketID)] ⚠️  Warning: Could not change status: \(error.localizedDescription)")
            }

            let duration = Date().timeIntervalSince(startTime)
            print("[\(ticketID)] ✅ Completed in \(Int(duration))s - \(prResult.url)")

            return .success(prURL: prResult.url, duration: duration)

        } catch {
            let duration = Date().timeIntervalSince(startTime)
            print("[\(ticketID)] ❌ Failed: \(error.localizedDescription)")
            return .failure(error: error, duration: duration)
        }
    }

    func createWorktree(for ticketID: String) async throws -> String {
        let sanitizedTicketID = ticketID.sanitizedForBranchName()
        let worktreePath = "/tmp/entrust-\(sanitizedTicketID)-\(UUID().uuidString.prefix(8))"
        let branch = "feature/\(sanitizedTicketID)"

        let githubService = GitHubService(configuration: githubConfig)
        try await githubService.createWorktree(
            path: worktreePath,
            branch: branch,
            baseBranch: githubConfig.baseBranch,
            in: repoRoot
        )

        return worktreePath
    }

    func runTests(in worktreePath: String) async throws {
        print("🔍 Running tests in directory: \(worktreePath)")

        // Verify the worktree path exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: worktreePath) {
            throw AutomationError.shellCommandFailed("Worktree path does not exist: \(worktreePath)")
        }

        // Detect project type
        let contents = try fileManager.contentsOfDirectory(atPath: worktreePath)
        let hasPackageSwift = contents.contains("Package.swift")
        let xcodeProjects = contents.filter { $0.hasSuffix(".xcodeproj") }
        let xcodeWorkspaces = contents.filter { $0.hasSuffix(".xcworkspace") }

        if hasPackageSwift {
            // Swift Package Manager project
            print("📦 Detected SPM project, running swift test...")
            let output = try await Shell.run(["swift", "test"], workingDirectory: worktreePath)

            if output.contains("FAILED") || output.contains("error:") {
                throw AutomationError.testsFailed
            }
        } else if !xcodeWorkspaces.isEmpty {
            // Xcode workspace
            let workspace = xcodeWorkspaces[0]
            print("🏗️  Detected Xcode workspace: \(workspace)")
            print("⚠️  Skipping tests - Xcode workspace testing requires specific scheme configuration")
            print("   To enable, configure your project with a test scheme and update this command")
            // Could run: xcodebuild test -workspace "\(workspace)" -scheme "<scheme>" -destination "platform=iOS Simulator,name=iPhone 15"
        } else if !xcodeProjects.isEmpty {
            // Xcode project
            let project = xcodeProjects[0]
            print("🏗️  Detected Xcode project: \(project)")
            print("⚠️  Skipping tests - Xcode project testing requires specific scheme configuration")
            print("   To enable, configure your project with a test scheme and update this command")
            // Could run: xcodebuild test -project "\(project)" -scheme "<scheme>" -destination "platform=iOS Simulator,name=iPhone 15"
        } else {
            print("⚠️  No recognizable project structure found")
            print("📂 Worktree contents:")
            print(contents.joined(separator: "\n"))
            throw AutomationError.shellCommandFailed("Unable to determine project type")
        }

        print("✅ Test step completed")
    }

    func buildPrompt(for issue: TaskIssue) -> String {
        """
        # Task: \(issue.title)

        ## Description
        \(issue.description ?? "No description provided")

        ## Instructions
        Please implement this feature completely. Follow these guidelines:
        - Write clean, well-structured code
        - Include appropriate error handling
        - Add comments where logic isn't self-evident
        - Ensure the code compiles without errors

        ## Pull Request Summary
        After completing the implementation, provide a summary for the pull request in the following format:

        **CONTEXT:**
        Explain the context and WHY this change is being made from a product perspective. What problem does this solve? What is the business value?

        **DESCRIPTION:**
        Provide a detailed technical description of HOW this task was accomplished. What specific steps were taken? Include details about implementation approach, architecture decisions, and integration points.

        **CHANGES:**
        List the specific technical changes made to the codebase:
        - What files were added/modified
        - What functionality was added or changed
        - Any refactoring or improvements made
        - Key implementation details

        When you're done, please confirm the implementation is complete and provide the PR summary.
        """
    }

    func buildPRBody(issue: TaskIssue, agentOutput: String) -> String {
        // Try to extract sections from Claude's output
        let context = extractSection(from: agentOutput, sectionName: "CONTEXT") ?? "Implements \(issue.title)"
        let description = extractSection(from: agentOutput, sectionName: "DESCRIPTION") ?? (issue.description ?? "No description provided")
        let changes = extractSection(from: agentOutput, sectionName: "CHANGES") ?? "See commit history for detailed changes"

        return """
        Resolves [\(issue.id)](\(taskTracker.baseURL)/issue/\(issue.id))

        ## Context
        \(context)

        ## Description
        \(description)

        ## Changes in the codebase
        \(changes)

        ---
        🤖 Automated by entrust (parallel mode) using Claude Code
        """
    }

    private func extractSection(from text: String, sectionName: String) -> String? {
        // Look for **SECTIONNAME:** or **SECTIONNAME**
        let patterns = [
            "\\*\\*\(sectionName):\\*\\*",
            "\\*\\*\(sectionName)\\*\\*"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

            if let match = matches.first {
                let startIndex = match.range.location + match.range.length

                // Find the next section or end of text
                let remainingText = String(nsText.substring(from: startIndex))

                // Look for next section marker or end
                let nextSectionPattern = "\\*\\*[A-Z]+:?\\*\\*"
                if let nextRegex = try? NSRegularExpression(pattern: nextSectionPattern, options: []),
                   let nextMatch = nextRegex.firstMatch(in: remainingText, range: NSRange(location: 0, length: (remainingText as NSString).length)) {
                    let endIndex = nextMatch.range.location
                    let section = (remainingText as NSString).substring(to: endIndex)
                    return section.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    // No next section, take rest of text
                    return remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return nil
    }

    func recordResult(ticket: String, result: TaskResult) {
        results[ticket] = result
    }

    func recordWorktree(_ path: String) {
        worktrees.append(path)
    }

    func printSummary() {
        print("\n")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 Summary")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let successful = results.values.filter { if case .success = $0 { return true }; return false }
        let failed = results.values.filter { if case .failure = $0 { return true }; return false }

        print("Total:      \(results.count)")
        print("Successful: \(successful.count) ✅")
        print("Failed:     \(failed.count) ❌")

        if !successful.isEmpty {
            print("\n✅ Successful:")
            for (ticket, result) in results where result.isSuccess {
                if case .success(let prURL, let duration) = result {
                    print("  • \(ticket) (\(Int(duration))s) - \(prURL)")
                }
            }
        }

        if !failed.isEmpty {
            print("\n❌ Failed:")
            for (ticket, result) in results where !result.isSuccess {
                if case .failure(let error, _) = result {
                    print("  • \(ticket) - \(error.localizedDescription)")
                }
            }
        }

        let totalDuration = results.values.reduce(0.0) { $0 + $1.duration }
        print("\nTotal time: \(Int(totalDuration))s")

        print("\n💡 Worktrees preserved:")
        for worktree in worktrees {
            print("  • \(worktree)")
        }
    }
}

enum TaskResult {
    case success(prURL: String, duration: TimeInterval)
    case failure(error: Error, duration: TimeInterval)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var duration: TimeInterval {
        switch self {
        case .success(_, let duration), .failure(_, let duration):
            return duration
        }
    }
}
