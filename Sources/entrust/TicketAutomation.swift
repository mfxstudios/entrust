import Foundation

struct TicketAutomation: Sendable {
    let ticketID: String
    let taskTracker: any TaskTracker
    let githubService: GitHubService
    let aiAgent: any AIAgent
    let skipTests: Bool
    let draft: Bool

    init(
        ticketID: String,
        taskTracker: any TaskTracker,
        githubService: GitHubService,
        aiAgent: any AIAgent,
        skipTests: Bool = false,
        draft: Bool = false
    ) {
        self.ticketID = ticketID
        self.taskTracker = taskTracker
        self.githubService = githubService
        self.aiAgent = aiAgent
        self.skipTests = skipTests
        self.draft = draft
    }

    func execute() async throws {
        print("🎫 Fetching ticket: \(ticketID)")
        let issue = try await taskTracker.fetchIssue(ticketID)

        print("\n📋 Task: \(issue.title)")
        print("Description: \(issue.description ?? "No description")\n")

        print("🔄 Moving ticket to 'In Progress'...")
        do {
            try await taskTracker.changeStatus(ticketID, to: "In Progress")
        } catch AutomationError.invalidStatus(let requested, let available) {
            print("⚠️  Warning: Could not move to '\(requested)'. Available: \(available.joined(separator: ", "))")
        } catch {
            print("⚠️  Warning: Could not change status: \(error.localizedDescription)")
        }

        // Create branch first
        print("\n🌿 Creating feature branch...")
        let sanitizedTicketID = ticketID.sanitizedForBranchName()
        let branch = "feature/\(sanitizedTicketID)"
        try await githubService.createBranch(
            name: branch,
            from: githubService.configuration.baseBranch,
            in: nil
        )

        // Build simple, direct prompt
        let prompt = buildPrompt(for: issue)

        // Run Claude Code directly in current directory
        print("\n🤖 Running Claude Code...\n")
        let agentResult = try await aiAgent.execute(
            prompt: prompt,
            context: AIAgentContext()
        )

        // Run tests if needed
        if !skipTests {
            print("\n\n🧪 Running tests...")
            try await runTests()
        }

        // Commit and push
        print("\n📤 Committing and pushing changes...")
        let hasChanges = try await githubService.commitAndPush(
            message: "[\(ticketID)] \(issue.title)",
            branch: branch,
            in: nil
        )

        guard hasChanges else {
            print("\n⚠️  No changes were made. Aborting PR creation.")
            return
        }

        // Create PR
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

        // Update issue
        print("\n✅ Updating ticket...")
        try await taskTracker.updateIssue(ticketID, prURL: prResult.url)

        print("\n🔄 Moving ticket to 'In Review'...")
        do {
            try await taskTracker.changeStatus(ticketID, to: "In Review")
        } catch AutomationError.invalidStatus(let requested, let available) {
            print("⚠️  Warning: Could not move to '\(requested)'. Available: \(available.joined(separator: ", "))")
        } catch {
            print("⚠️  Warning: Could not change status: \(error.localizedDescription)")
        }

        print("\n🎉 Done! PR created: \(prResult.url)")
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

        When you're done, please confirm the implementation is complete.
        """
    }

    func runTests() async throws {
        let output = try await Shell.run("swift", "test")

        if output.contains("FAILED") || output.contains("error:") {
            throw AutomationError.testsFailed
        }

        print("✅ All tests passed")
    }

    func buildPRBody(issue: TaskIssue, agentOutput: String) -> String {
        """
        Resolves [\(issue.id)](\(taskTracker.baseURL)/issue/\(issue.id))

        ## Summary
        \(issue.title)

        ## Description
        \(issue.description ?? "")

        ---
        🤖 Automated by entrust using Claude Code
        """
    }
}
