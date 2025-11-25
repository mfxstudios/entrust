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

    @Option(name: .long, help: "Override GitHub repository (org/repo)")
    var repo: String?

    @Option(name: .long, help: "Override base branch for PR")
    var baseBranch: String?

    @Option(name: .long, help: "Override AI agent [claude-code/aider/cursor/custom]")
    var aiAgent: String?

    @Flag(name: .long, help: "Override: Use GitHub CLI instead of API")
    var useGHCLI: Bool = false

    @Flag(name: .long, help: "Override: Skip running tests")
    var skipTests: Bool = false

    @Flag(name: .long, help: "Override: Create draft PR")
    var draft: Bool = false

    @Flag(name: .long, help: "Dry run - show execution plan without running")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Keep worktrees after completion (for debugging)")
    var keepWorktrees: Bool = false

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
            throw AutomationError.noTicketsProvided
        }

        // Remove duplicates while preserving order
        allTickets = Array(NSOrderedSet(array: allTickets)) as! [String]

        print("🎫 Processing \(allTickets.count) ticket(s) with max \(maxConcurrent) concurrent")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        // Setup task tracker
        let taskTracker: any TaskTracker

        if config.trackerType == "jira" {
            guard let jiraURL = config.jiraURL, let jiraEmail = config.jiraEmail else {
                throw AutomationError.missingJIRAConfiguration
            }
            let jiraToken = try KeychainManager.load(.jiraToken)
            taskTracker = JIRATracker(url: jiraURL, email: jiraEmail, token: jiraToken)
        } else if config.trackerType == "reminders" {
            guard let listName = config.remindersListName else {
                throw AutomationError.missingRemindersConfiguration
            }
            taskTracker = RemindersTracker(listName: listName)
        } else {
            let linearToken = try KeychainManager.load(.linearToken)
            taskTracker = LinearTracker(token: linearToken)
        }

        let effectiveRepo = repo ?? config.repo
        let effectiveBaseBranch = baseBranch ?? config.baseBranch
        let effectiveUseGHCLI = useGHCLI || config.useGHCLI
        let effectiveSkipTests = skipTests || !config.runTestsByDefault
        let effectiveDraft = draft || config.autoCreateDraft
        let effectiveAIAgent = aiAgent ?? config.aiAgentType ?? "claude-code"
        let githubToken = effectiveUseGHCLI ? nil : try? KeychainManager.load(.githubToken)

        // Create AI agent
        let agentType = AIAgentType(rawValue: effectiveAIAgent) ?? .claudeCode
        let agent = AIAgentFactory.create(type: agentType)

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
            print("AI Agent: \(agent.name)")
            print("Repository: \(effectiveRepo)")
            print("Base Branch: \(effectiveBaseBranch)\n")
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
            aiAgent: agent,
            promptTemplate: DefaultPromptTemplate(),
            skipTests: effectiveSkipTests,
            maxConcurrent: maxConcurrent,
            keepWorktrees: keepWorktrees
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
    let promptTemplate: PromptTemplate
    let skipTests: Bool
    let maxConcurrent: Int
    let keepWorktrees: Bool

    private var results: [String: TaskResult] = [:]
    private var worktrees: [String] = []

    init(
        tickets: [String],
        repoRoot: String,
        taskTracker: any TaskTracker,
        githubConfig: GitHubConfiguration,
        aiAgent: any AIAgent,
        promptTemplate: PromptTemplate,
        skipTests: Bool,
        maxConcurrent: Int,
        keepWorktrees: Bool
    ) {
        self.tickets = tickets
        self.repoRoot = repoRoot
        self.taskTracker = taskTracker
        self.githubConfig = githubConfig
        self.aiAgent = aiAgent
        self.promptTemplate = promptTemplate
        self.skipTests = skipTests
        self.maxConcurrent = maxConcurrent
        self.keepWorktrees = keepWorktrees
    }

    func execute() async throws {
        defer {
            if !keepWorktrees {
                cleanupWorktrees()
            }
        }

        // Capture values needed for concurrent tasks
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

            // Run AI agent in worktree
            print("[\(ticketID)] 🤖 Running \(aiAgent.name)...")
            let prompt = buildPrompt(for: issue)
            let agentResult = try await aiAgent.execute(
                prompt: prompt,
                context: AIAgentContext(workingDirectory: worktreePath)
            )

            // Run tests
            if !skipTests {
                print("[\(ticketID)] 🧪 Running tests...")
                try await runTests(in: worktreePath)
            }

            // Commit and push using GitHub service
            print("[\(ticketID)] 🌿 Committing and pushing...")
            let sanitizedTicketID = ticketID.sanitizedForBranchName()
            let branch = "feature/\(sanitizedTicketID)"
            let githubService = GitHubService(configuration: githubConfig)
            try await githubService.commitAndPush(
                message: "[\(ticketID)] Automated implementation",
                branch: branch,
                in: worktreePath
            )

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
        let output = try await Shell.runInDirectory(worktreePath, command: "swift test")

        if output.contains("FAILED") || output.contains("error:") {
            throw AutomationError.testsFailed
        }
    }

    func buildPrompt(for issue: TaskIssue) -> String {
        let variables = PromptVariables(from: issue)
        return promptTemplate.render(with: variables)
    }

    func buildPRBody(issue: TaskIssue, agentOutput: String) -> String {
        """
        Resolves [\(issue.id)](\(taskTracker.baseURL)/issue/\(issue.id))

        ## Summary
        \(issue.title)

        ## Description
        \(issue.description ?? "")

        ## Implementation Details
        \(agentOutput)

        ---
        🤖 This PR was automatically generated by entrust (parallel mode) using \(aiAgent.name)
        """
    }

    func recordResult(ticket: String, result: TaskResult) {
        results[ticket] = result
    }

    func recordWorktree(_ path: String) {
        worktrees.append(path)
    }

    func cleanupWorktrees() {
        print("\n🧹 Cleaning up worktrees...")
        for worktree in worktrees {
            do {
                try FileManager.default.removeItem(atPath: worktree)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git", "-C", repoRoot, "worktree", "prune"]
                try process.run()
                process.waitUntilExit()
            } catch {
                print("⚠️  Failed to cleanup \(worktree): \(error)")
            }
        }
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

        if keepWorktrees {
            print("\n💡 Worktrees preserved for debugging:")
            for worktree in worktrees {
                print("  • \(worktree)")
            }
            print("\nCleanup with: git worktree prune && rm -rf /tmp/entrust-*")
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
