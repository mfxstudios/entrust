import Foundation

struct TicketAutomation: Sendable {
    let ticketID: String
    let repoRoot: String
    let taskTracker: any TaskTracker
    let githubService: GitHubService
    let aiAgent: any AIAgent
    let promptTemplate: PromptTemplate
    let skipTests: Bool
    let draft: Bool
    let keepWorktree: Bool

    init(
        ticketID: String,
        repoRoot: String,
        taskTracker: any TaskTracker,
        githubService: GitHubService,
        aiAgent: any AIAgent,
        promptTemplate: PromptTemplate = DefaultPromptTemplate(),
        skipTests: Bool = false,
        draft: Bool = false,
        keepWorktree: Bool = false
    ) {
        self.ticketID = ticketID
        self.repoRoot = repoRoot
        self.taskTracker = taskTracker
        self.githubService = githubService
        self.aiAgent = aiAgent
        self.promptTemplate = promptTemplate
        self.skipTests = skipTests
        self.draft = draft
        self.keepWorktree = keepWorktree
    }

    /// Convenience initializer using Configuration
    init(
        ticketID: String,
        repoRoot: String,
        taskTracker: any TaskTracker,
        config: Configuration,
        githubToken: String?,
        skipTests: Bool = false,
        draft: Bool = false,
        keepWorktree: Bool = false
    ) {
        self.ticketID = ticketID
        self.repoRoot = repoRoot
        self.taskTracker = taskTracker
        self.githubService = GitHubService(
            configuration: config.getGitHubConfiguration(token: githubToken, draft: draft)
        )
        self.aiAgent = config.getAIAgent()
        self.promptTemplate = DefaultPromptTemplate()
        self.skipTests = skipTests
        self.draft = draft
        self.keepWorktree = keepWorktree
    }

    func execute() async throws {
        print("🎫 Fetching ticket: \(ticketID)")
        let issue = try await taskTracker.fetchIssue(ticketID)

        print("\n📋 Task: \(issue.title)")

        print("\n🔄 Moving ticket to 'In Progress'...")
        do {
            try await taskTracker.changeStatus(ticketID, to: "In Progress")
        } catch AutomationError.invalidStatus(let requested, let available) {
            print("⚠️  Warning: Could not move to '\(requested)'. Available statuses: \(available.joined(separator: ", "))")
        } catch {
            print("⚠️  Warning: Could not change status: \(error.localizedDescription)")
        }

        // Create worktree for isolated execution
        print("\n🌿 Creating worktree...")
        let sanitizedTicketID = ticketID.sanitizedForBranchName()
        let worktreePath = "/tmp/entrust-\(sanitizedTicketID)-\(UUID().uuidString.prefix(8))"
        let branch = "feature/\(sanitizedTicketID)"

        defer {
            if !keepWorktree {
                cleanupWorktree(path: worktreePath)
            } else {
                print("\n💡 Worktree preserved at: \(worktreePath)")
                print("   Cleanup with: git worktree prune && rm -rf \(worktreePath)")
            }
        }

        do {
            try await githubService.createWorktree(
                path: worktreePath,
                branch: branch,
                baseBranch: githubService.configuration.baseBranch,
                in: repoRoot
            )
        } catch {
            print("❌ Failed to create worktree: \(error.localizedDescription)")
            throw error
        }

        print("\n🤖 Running \(aiAgent.name) in worktree...")
        let prompt = buildPrompt(for: issue)
        let agentResult = try await aiAgent.execute(
            prompt: prompt,
            context: AIAgentContext(workingDirectory: worktreePath)
        )

        if !skipTests {
            print("\n🧪 Running tests in worktree...")
            try await runTests(in: worktreePath)
        }

        print("\n📤 Committing and pushing changes...")
        let hasChanges = try await githubService.commitAndPush(
            message: "[\(ticketID)] Automated implementation",
            branch: branch,
            in: worktreePath
        )

        guard hasChanges else {
            print("\n⚠️  No changes were made by the AI agent. Aborting PR creation.")
            print("   This could mean:")
            print("   - The AI agent didn't make any code changes")
            print("   - The task might already be completed")
            print("   - There was an issue with the AI agent execution")
            return
        }

        print("\n📬 Creating pull request...")
        let prResult = try await githubService.createPullRequest(
            PullRequestParams(
                title: "[\(ticketID)] \(issue.title)",
                body: buildPRBody(issue: issue, agentOutput: agentResult.output),
                branch: branch,
                baseBranch: githubService.configuration.baseBranch,
                draft: draft
            )
        )

        print("\n✅ Updating ticket...")
        try await taskTracker.updateIssue(ticketID, prURL: prResult.url)

        print("\n🔄 Moving ticket to 'In Review'...")
        do {
            try await taskTracker.changeStatus(ticketID, to: "In Review")
        } catch AutomationError.invalidStatus(let requested, let available) {
            print("⚠️  Warning: Could not move to '\(requested)'. Available statuses: \(available.joined(separator: ", "))")
        } catch {
            print("⚠️  Warning: Could not change status: \(error.localizedDescription)")
        }

        print("\n🎉 Done! PR created: \(prResult.url)")
    }

    func buildPrompt(for issue: TaskIssue) -> String {
        let variables = PromptVariables(from: issue)
        return promptTemplate.render(with: variables)
    }

    func runTests(in worktreePath: String) async throws {
        let output = try await Shell.runInDirectory(worktreePath, command: "swift test")

        if output.contains("FAILED") || output.contains("error:") {
            throw AutomationError.testsFailed
        }

        print("✅ All tests passed")
    }

    func cleanupWorktree(path: String) {
        do {
            print("\n🧹 Cleaning up worktree...")
            try FileManager.default.removeItem(atPath: path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "-C", repoRoot, "worktree", "prune"]
            try process.run()
            process.waitUntilExit()
        } catch {
            print("⚠️  Failed to cleanup worktree: \(error)")
        }
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
        🤖 This PR was automatically generated by entrust using \(aiAgent.name)
        """
    }
}
