import Foundation

struct TicketAutomation: Sendable {
    let ticketID: String
    let repoRoot: String
    let taskTracker: any TaskTracker
    let githubService: GitHubService
    let aiAgent: any AIAgent
    let skipTests: Bool
    let draft: Bool
    let maxRetryAttempts: Int

    init(
        ticketID: String,
        repoRoot: String,
        taskTracker: any TaskTracker,
        githubService: GitHubService,
        aiAgent: any AIAgent,
        skipTests: Bool = false,
        draft: Bool = false,
        maxRetryAttempts: Int = 3
    ) {
        self.ticketID = ticketID
        self.repoRoot = repoRoot
        self.taskTracker = taskTracker
        self.githubService = githubService
        self.aiAgent = aiAgent
        self.skipTests = skipTests
        self.draft = draft
        self.maxRetryAttempts = maxRetryAttempts
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

        // Create worktree for isolated execution
        print("\n🌿 Creating worktree...")
        let sanitizedTicketID = ticketID.sanitizedForBranchName()
        let worktreePath = "/tmp/entrust-\(sanitizedTicketID)-\(UUID().uuidString.prefix(8))"
        let branch = "feature/\(sanitizedTicketID)"

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

        print("💡 Worktree created at: \(worktreePath)")

        // Build prompt
        let prompt = buildPrompt(for: issue)

        // Run Claude Code in worktree
        print("\n🤖 Running Claude Code in worktree: \(worktreePath)\n")
        var agentResult = try await aiAgent.execute(
            prompt: prompt,
            context: AIAgentContext(workingDirectory: worktreePath)
        )

        // Check what files changed
        print("\n📝 Checking for changes...")
        let gitStatus = try await Shell.run(["git", "status", "--short"], workingDirectory: worktreePath)
        if !gitStatus.isEmpty {
            print("Changes detected:")
            print(gitStatus)
        } else {
            print("⚠️  No files were modified by Claude Code")
        }

        // Run tests if needed with automatic retry on failure
        if !skipTests {
            print("\n\n🧪 Running tests in worktree...")

            var attempt = 0

            while attempt < maxRetryAttempts {
                do {
                    try await runTests(in: worktreePath)
                    if attempt > 0 {
                        print("✅ Tests passed after \(attempt) fix attempt(s)!")
                    }
                    break // Tests passed, exit loop
                } catch {
                    attempt += 1

                    // Tests failed - try to fix automatically using multi-turn
                    if let sessionId = agentResult.sessionId, attempt < maxRetryAttempts {
                        print("\n⚠️  Tests failed (attempt \(attempt)/\(maxRetryAttempts)): \(error.localizedDescription)")
                        print("🔄 Asking Claude to fix the test failures...\n")

                        let fixPrompt = """
                        The tests failed with the following error:
                        \(error.localizedDescription)

                        Please fix the code to make the tests pass. Review what you implemented and correct any issues.
                        \(attempt > 1 ? "This is attempt \(attempt), please look more carefully at the error." : "")
                        """

                        agentResult = try await aiAgent.continueConversation(
                            sessionId: sessionId,
                            prompt: fixPrompt,
                            context: AIAgentContext(workingDirectory: worktreePath)
                        )

                        print("\n🧪 Running tests again (attempt \(attempt + 1))...")
                    } else if attempt >= maxRetryAttempts {
                        print("\n❌ Tests failed after \(maxRetryAttempts) attempts")
                        throw error
                    } else {
                        // No session ID, can't continue conversation
                        print("\n❌ Tests failed and cannot auto-fix (no session ID)")
                        throw error
                    }
                }
            }
        }

        // Commit and push
        print("\n📤 Committing and pushing changes...")
        let hasChanges = try await githubService.commitAndPush(
            message: "[\(ticketID)] \(issue.title)",
            branch: branch,
            in: worktreePath
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
        🤖 Automated by entrust using Claude Code
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
}
