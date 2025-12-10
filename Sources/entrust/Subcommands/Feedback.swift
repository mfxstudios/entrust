import ArgumentParser
import Foundation
import ClaudeCodeSDK

struct Feedback: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Address PR feedback by continuing the Claude Code session"
    )

    @Argument(help: "PR number or full GitHub URL (e.g., 456 or https://github.com/org/repo/pull/456)")
    var prIdentifier: String

    @Option(name: .long, help: "Repository root directory")
    var repoRoot: String?

    @Flag(name: .long, help: "Process all comments, including already processed ones")
    var all: Bool = false

    func run() async throws {
        let config = try ConfigurationManager.load()

        // Determine repo root
        let effectiveRepoRoot: String
        if let repoRoot = repoRoot {
            effectiveRepoRoot = repoRoot
        } else {
            effectiveRepoRoot = FileManager.default.currentDirectoryPath
        }

        print("🔄 Processing PR feedback...\n")

        // Parse PR identifier (number or URL)
        let prURL: String
        let prNumber: Int

        if prIdentifier.starts(with: "http://") || prIdentifier.starts(with: "https://") {
            // Full URL provided
            prURL = prIdentifier
            guard let extractedNumber = extractPRNumber(from: prURL) else {
                throw AutomationError.shellCommandFailed("Invalid PR URL format")
            }
            prNumber = extractedNumber
        } else {
            // Just a number provided - construct URL from git remote
            guard let number = Int(prIdentifier) else {
                throw AutomationError.shellCommandFailed("PR identifier must be a number or full URL")
            }
            prNumber = number

            // Detect repo from git remote
            let remoteURL = try await Shell.run(
                ["git", "config", "--get", "remote.origin.url"],
                workingDirectory: effectiveRepoRoot
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let repoPath = extractRepoPath(from: remoteURL) else {
                throw AutomationError.shellCommandFailed("Could not extract repo path from git remote")
            }

            prURL = "https://github.com/\(repoPath)/pull/\(prNumber)"
        }

        print("📬 PR: \(prURL)\n")

        // Initialize services
        let githubService = GitHubService(configuration: config.getGitHubConfiguration(token: nil))
        let storage = PRSessionStorage()

        // Fetch PR metadata
        print("📥 Fetching PR details...")
        let pr = try await githubService.fetchPullRequest(prNumber)
        print("📋 Title: \(pr.title)")
        print("🌿 Branch: \(pr.headBranch)\n")

        // Get session info
        print("🔍 Looking up Claude session...")
        var sessionInfo = try storage.get(prURL: prURL)

        // Fallback: check PR description for session ID
        if sessionInfo == nil {
            if let sessionId = storage.extractSessionFromPRDescription(pr.body) {
                print("ℹ️  Found session ID in PR description: \(sessionId.prefix(8))...")
                // Create minimal session info from PR data
                sessionInfo = PRSessionInfo(
                    sessionId: sessionId,
                    ticketId: extractTicketID(from: pr.title) ?? "UNKNOWN",
                    branch: pr.headBranch,
                    createdAt: Date(),
                    skipTests: false
                )
            }
        }

        guard let sessionInfo = sessionInfo else {
            print("❌ No session found for this PR")
            print("   Session data not found in local storage or PR description")
            print("   This PR may not have been created by entrust")
            throw AutomationError.configurationNotFound
        }

        print("✅ Found session: \(sessionInfo.sessionId.prefix(8))...")
        print("🎫 Ticket: \(sessionInfo.ticketId)\n")

        // Fetch comments
        print("💬 Fetching PR comments...")
        let comments = try await githubService.fetchPRComments(prNumber)

        // Filter comments
        let processedIDs = all ? [] : sessionInfo.lastProcessedComments
        let newComments = filterActionableComments(comments, excluding: processedIDs)

        if newComments.isEmpty {
            print("✅ No new actionable feedback found")
            print("   All comments have been processed or don't require action")
            return
        }

        print("📝 Found \(newComments.count) actionable comment(s)\n")

        // Format feedback prompt
        let feedbackPrompt = buildFeedbackPrompt(comments: newComments, ticketID: sessionInfo.ticketId)

        // Create/recreate worktree
        print("🌿 Setting up worktree for branch: \(sessionInfo.branch)...")
        let sanitizedBranch = sessionInfo.branch.replacingOccurrences(of: "/", with: "-")
        let worktreePath = "/tmp/entrust-feedback-\(sanitizedBranch)-\(UUID().uuidString.prefix(8))"

        do {
            try await githubService.createWorktree(
                path: worktreePath,
                branch: sessionInfo.branch,
                baseBranch: nil as String?, // Don't create new branch, use existing
                in: effectiveRepoRoot
            )
        } catch {
            print("❌ Failed to create worktree: \(error.localizedDescription)")
            throw error
        }

        print("💡 Worktree created at: \(worktreePath)\n")

        // Continue Claude conversation
        let aiAgent = AIAgentFactory.create(type: .claudeCode)
        var agentResult = try await aiAgent.continueConversation(
            sessionId: sessionInfo.sessionId,
            prompt: feedbackPrompt,
            context: AIAgentContext(workingDirectory: worktreePath)
        )

        // Run tests if needed
        if !sessionInfo.skipTests {
            print("\n\n🧪 Running tests in worktree...")
            var attempt = 0
            let maxRetryAttempts = config.maxRetryAttempts

            while attempt < maxRetryAttempts {
                do {
                    try await runTests(in: worktreePath)
                    if attempt > 0 {
                        print("✅ Tests passed after \(attempt) fix attempt(s)!")
                    }
                    break
                } catch {
                    attempt += 1

                    if let newSessionId = agentResult.sessionId, attempt < maxRetryAttempts {
                        print("\n⚠️  Tests failed (attempt \(attempt)/\(maxRetryAttempts)): \(error.localizedDescription)")
                        print("🔄 Asking Claude to fix the test failures...\n")

                        let fixPrompt = """
                        The tests failed with the following error:
                        \(error.localizedDescription)

                        Please fix the code to make the tests pass. Review what you implemented and correct any issues.
                        \(attempt > 1 ? "This is attempt \(attempt), please look more carefully at the error." : "")
                        """

                        agentResult = try await aiAgent.continueConversation(
                            sessionId: newSessionId,
                            prompt: fixPrompt,
                            context: AIAgentContext(workingDirectory: worktreePath)
                        )

                        print("\n🧪 Running tests again (attempt \(attempt + 1))...")
                    } else if attempt >= maxRetryAttempts {
                        print("\n❌ Tests failed after \(maxRetryAttempts) attempts")
                        throw error
                    } else {
                        print("\n❌ Tests failed and cannot auto-fix (no session ID)")
                        throw error
                    }
                }
            }
        }

        // Commit and push
        print("\n📤 Committing and pushing changes...")
        let hasChanges = try await githubService.commitAndPush(
            message: "[\(sessionInfo.ticketId)] Address PR feedback",
            branch: sessionInfo.branch,
            in: worktreePath
        )

        guard hasChanges else {
            print("\n⚠️  No changes were made")
            return
        }

        // Update session storage
        print("\n💾 Updating session data...")
        if let newSessionId = agentResult.sessionId {
            try storage.updateSessionId(prURL: prURL, newSessionId: newSessionId)
        }

        let newCommentIDs = newComments.map { $0.id }
        try storage.updateProcessedComments(prURL: prURL, commentIDs: newCommentIDs)

        print("\n🎉 Done! Changes pushed to \(sessionInfo.branch)")
        print("   View PR: \(prURL)")
    }

    private func extractPRNumber(from url: String) -> Int? {
        // Extract number from URL like https://github.com/org/repo/pull/456
        let pattern = "/pull/(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let range = Range(match.range(at: 1), in: url) else {
            return nil
        }
        return Int(url[range])
    }

    private func extractRepoPath(from remoteURL: String) -> String? {
        // Handle both SSH and HTTPS URLs
        // SSH: git@github.com:org/repo.git
        // HTTPS: https://github.com/org/repo.git

        if remoteURL.starts(with: "git@github.com:") {
            let path = remoteURL.replacingOccurrences(of: "git@github.com:", with: "")
            return path.replacingOccurrences(of: ".git", with: "")
        } else if remoteURL.starts(with: "https://github.com/") {
            let path = remoteURL.replacingOccurrences(of: "https://github.com/", with: "")
            return path.replacingOccurrences(of: ".git", with: "")
        }

        return nil
    }

    private func extractTicketID(from title: String) -> String? {
        // Extract [TICKET-123] from title
        let pattern = "\\[([A-Z]+-\\d+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return String(title[range])
    }

    private func filterActionableComments(_ comments: [PRComment], excluding processedIDs: [Int]) -> [PRComment] {
        comments.filter { comment in
            // Skip if already processed
            guard !processedIDs.contains(comment.id) else {
                return false
            }

            let body = comment.body.lowercased()

            // Check for triggers: **entrust**, **entrust:**, or entrust:
            let hasBoldTrigger = body.contains("**entrust**") || body.contains("**entrust:**")
            let hasPrefixTrigger = body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("entrust:")

            // Check if from "Request Changes" review
            let isFromRequestChanges = comment.isFromRequestChangesReview

            return hasBoldTrigger || hasPrefixTrigger || isFromRequestChanges
        }
    }

    private func buildFeedbackPrompt(comments: [PRComment], ticketID: String) -> String {
        var prompt = "The PR received code review feedback. Please address the following comments:\n\n"

        // Group comments by review state
        let requestChangesComments = comments.filter { $0.isFromRequestChangesReview }
        let triggeredComments = comments.filter { !$0.isFromRequestChangesReview }

        if !requestChangesComments.isEmpty {
            prompt += "[From reviews requesting changes:]\n\n"
            for comment in requestChangesComments {
                if let path = comment.path, let line = comment.line {
                    prompt += "File: \(path), Line: \(line)\n"
                }
                prompt += "@\(comment.author): \(comment.body)\n\n"
            }
        }

        if !triggeredComments.isEmpty {
            prompt += "[From comments with entrust trigger:]\n\n"
            for comment in triggeredComments {
                if let path = comment.path, let line = comment.line {
                    prompt += "File: \(path), Line: \(line)\n"
                }
                prompt += "@\(comment.author): \(comment.body)\n\n"
            }
        }

        prompt += """
        ---

        Please make the necessary changes to address this feedback. Follow the same coding standards you used in the original implementation.

        If any feedback is unclear or requires discussion, explain what clarification you need.
        """

        return prompt
    }

    private func runTests(in worktreePath: String) async throws {
        print("🔍 Running tests in directory: \(worktreePath)")

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: worktreePath) {
            throw AutomationError.shellCommandFailed("Worktree path does not exist: \(worktreePath)")
        }

        let contents = try fileManager.contentsOfDirectory(atPath: worktreePath)
        let hasPackageSwift = contents.contains("Package.swift")

        if hasPackageSwift {
            print("📦 Detected SPM project, running swift test...")
            let output = try await Shell.run(["swift", "test"], workingDirectory: worktreePath)

            if output.contains("FAILED") || output.contains("error:") {
                throw AutomationError.testsFailed
            }
        } else {
            print("⚠️  No Package.swift found, skipping tests")
        }

        print("✅ Test step completed")
    }
}
