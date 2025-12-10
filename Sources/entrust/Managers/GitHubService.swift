import Foundation

/// Configuration for GitHub operations
struct GitHubConfiguration: Sendable {
    let repo: String
    let baseBranch: String
    let useGHCLI: Bool
    let token: String?
    let draft: Bool

    init(
        repo: String,
        baseBranch: String,
        useGHCLI: Bool = true,
        token: String? = nil,
        draft: Bool = false
    ) {
        self.repo = repo
        self.baseBranch = baseBranch
        self.useGHCLI = useGHCLI
        self.token = token
        self.draft = draft
    }
}

/// Pull request creation parameters
struct PullRequestParams: Sendable {
    let title: String
    let body: String
    let branch: String
    let baseBranch: String
    let draft: Bool
}

/// Result of a pull request creation
struct PullRequestResult: Sendable {
    let url: String
    let number: Int?
}

/// Pull request details
struct PullRequest: Sendable {
    let number: Int
    let title: String
    let body: String
    let headBranch: String
    let baseBranch: String
    let state: String
}

/// Pull request comment
struct PRComment: Sendable {
    let id: Int
    let body: String
    let author: String
    let path: String?
    let line: Int?
    let isFromRequestChangesReview: Bool
}

/// Protocol for GitHub operations - enables testing and alternative implementations
protocol GitHubServiceProtocol: Sendable {
    var configuration: GitHubConfiguration { get }

    func createPullRequest(_ params: PullRequestParams) async throws -> PullRequestResult
    func createBranch(name: String, from baseBranch: String, in workingDirectory: String?) async throws
    func commitAndPush(message: String, branch: String, in workingDirectory: String?) async throws -> Bool
    func fetchLatest(branch: String, in workingDirectory: String?) async throws
    func fetchPullRequest(_ number: Int) async throws -> PullRequest
    func fetchPRComments(_ number: Int) async throws -> [PRComment]
}

/// GitHub service implementation using either GitHub CLI or REST API
struct GitHubService: GitHubServiceProtocol, Sendable {
    let configuration: GitHubConfiguration

    init(configuration: GitHubConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Pull Request Operations

    func createPullRequest(_ params: PullRequestParams) async throws -> PullRequestResult {
        if configuration.useGHCLI {
            return try await createPRWithGHCLI(params)
        } else {
            return try await createPRWithAPI(params)
        }
    }

    private func createPRWithGHCLI(_ params: PullRequestParams) async throws -> PullRequestResult {
        var args = [
            "gh", "pr", "create",
            "--repo", configuration.repo,
            "--title", params.title,
            "--body", params.body,
            "--base", params.baseBranch,
            "--head", params.branch
        ]

        if params.draft {
            args.append("--draft")
        }

        let output = try await Shell.run(args)
        let url = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract PR number from URL if possible
        let number = extractPRNumber(from: url)

        return PullRequestResult(url: url, number: number)
    }

    private func createPRWithAPI(_ params: PullRequestParams) async throws -> PullRequestResult {
        guard let token = configuration.token else {
            throw AutomationError.missingGitHubToken
        }

        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(configuration.repo)/pulls")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let payload: [String: Any] = [
            "title": params.title,
            "body": params.body,
            "head": params.branch,
            "base": params.baseBranch,
            "draft": params.draft
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AutomationError.prCreationFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let url = json["html_url"] as! String
        let number = json["number"] as? Int

        return PullRequestResult(url: url, number: number)
    }

    func fetchPullRequest(_ number: Int) async throws -> PullRequest {
        if configuration.useGHCLI {
            return try await fetchPRWithGHCLI(number)
        } else {
            return try await fetchPRWithAPI(number)
        }
    }

    private func fetchPRWithGHCLI(_ number: Int) async throws -> PullRequest {
        let output = try await Shell.run([
            "gh", "pr", "view", "\(number)",
            "--repo", configuration.repo,
            "--json", "number,title,body,headRefName,baseRefName,state"
        ])

        guard let data = output.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AutomationError.shellCommandFailed("Failed to parse PR data")
        }

        return PullRequest(
            number: json["number"] as? Int ?? number,
            title: json["title"] as? String ?? "",
            body: json["body"] as? String ?? "",
            headBranch: json["headRefName"] as? String ?? "",
            baseBranch: json["baseRefName"] as? String ?? "",
            state: json["state"] as? String ?? ""
        )
    }

    private func fetchPRWithAPI(_ number: Int) async throws -> PullRequest {
        guard let token = configuration.token else {
            throw AutomationError.missingGitHubToken
        }

        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(configuration.repo)/pulls/\(number)")!
        )
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AutomationError.shellCommandFailed("Failed to fetch PR")
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let head = json["head"] as! [String: Any]
        let base = json["base"] as! [String: Any]

        return PullRequest(
            number: json["number"] as? Int ?? number,
            title: json["title"] as? String ?? "",
            body: json["body"] as? String ?? "",
            headBranch: head["ref"] as? String ?? "",
            baseBranch: base["ref"] as? String ?? "",
            state: json["state"] as? String ?? ""
        )
    }

    func fetchPRComments(_ number: Int) async throws -> [PRComment] {
        if configuration.useGHCLI {
            return try await fetchCommentsWithGHCLI(number)
        } else {
            return try await fetchCommentsWithAPI(number)
        }
    }

    private func fetchCommentsWithGHCLI(_ number: Int) async throws -> [PRComment] {
        // Fetch review comments (inline code comments)
        let reviewCommentsOutput = try await Shell.run([
            "gh", "api",
            "/repos/\(configuration.repo)/pulls/\(number)/comments",
            "--jq", """
            .[] | {
                id: .id,
                body: .body,
                author: .user.login,
                path: .path,
                line: .line,
                commit_id: .commit_id
            }
            """
        ])

        // Fetch reviews to determine which comments are from "Request Changes" reviews
        let reviewsOutput = try await Shell.run([
            "gh", "api",
            "/repos/\(configuration.repo)/pulls/\(number)/reviews",
            "--jq", """
            .[] | select(.state == "CHANGES_REQUESTED") | {
                id: .id,
                commit_id: .commit_id
            }
            """
        ])

        // Parse review comments
        var comments: [PRComment] = []
        let reviewCommentLines = reviewCommentsOutput.split(separator: "\n")

        // Build set of commit IDs from "Request Changes" reviews
        var requestChangesCommitIDs = Set<String>()
        let reviewLines = reviewsOutput.split(separator: "\n")
        for line in reviewLines {
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let commitID = json["commit_id"] as? String {
                requestChangesCommitIDs.insert(commitID)
            }
        }

        for line in reviewCommentLines {
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                let commitID = json["commit_id"] as? String ?? ""
                let isFromRequestChanges = requestChangesCommitIDs.contains(commitID)

                comments.append(PRComment(
                    id: json["id"] as? Int ?? 0,
                    body: json["body"] as? String ?? "",
                    author: json["author"] as? String ?? "",
                    path: json["path"] as? String,
                    line: json["line"] as? Int,
                    isFromRequestChangesReview: isFromRequestChanges
                ))
            }
        }

        return comments
    }

    private func fetchCommentsWithAPI(_ number: Int) async throws -> [PRComment] {
        guard let token = configuration.token else {
            throw AutomationError.missingGitHubToken
        }

        // Fetch review comments
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(configuration.repo)/pulls/\(number)/comments")!
        )
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (commentsData, _) = try await URLSession.shared.data(for: request)
        let commentsJSON = try JSONSerialization.jsonObject(with: commentsData) as! [[String: Any]]

        // Fetch reviews to determine "Request Changes" state
        var reviewsRequest = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(configuration.repo)/pulls/\(number)/reviews")!
        )
        reviewsRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        reviewsRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (reviewsData, _) = try await URLSession.shared.data(for: reviewsRequest)
        let reviewsJSON = try JSONSerialization.jsonObject(with: reviewsData) as! [[String: Any]]

        // Build set of commit IDs from "Request Changes" reviews
        var requestChangesCommitIDs = Set<String>()
        for review in reviewsJSON {
            if let state = review["state"] as? String,
               state == "CHANGES_REQUESTED",
               let commitID = review["commit_id"] as? String {
                requestChangesCommitIDs.insert(commitID)
            }
        }

        // Parse comments
        var comments: [PRComment] = []
        for commentJSON in commentsJSON {
            let commitID = commentJSON["commit_id"] as? String ?? ""
            let isFromRequestChanges = requestChangesCommitIDs.contains(commitID)

            let user = commentJSON["user"] as? [String: Any]

            comments.append(PRComment(
                id: commentJSON["id"] as? Int ?? 0,
                body: commentJSON["body"] as? String ?? "",
                author: user?["login"] as? String ?? "",
                path: commentJSON["path"] as? String,
                line: commentJSON["line"] as? Int,
                isFromRequestChangesReview: isFromRequestChanges
            ))
        }

        return comments
    }

    // MARK: - Branch Operations

    func createBranch(name: String, from baseBranch: String, in workingDirectory: String? = nil) async throws {
        let gitArgs = gitCommand(for: workingDirectory)

        try await Shell.run(gitArgs + ["checkout", baseBranch])
        try await Shell.run(gitArgs + ["pull", "origin", baseBranch])
        try await Shell.run(gitArgs + ["checkout", "-b", name])
    }

    func commitAndPush(message: String, branch: String, in workingDirectory: String? = nil) async throws -> Bool {
        print("📋 Staging changes in \(workingDirectory ?? "current directory")...")

        // Stage all changes
        try await Shell.run(["git", "add", "."], workingDirectory: workingDirectory)

        // Check if there are any changes to commit
        print("🔍 Checking git status...")
        let status = try await Shell.run(["git", "status", "--porcelain"], workingDirectory: workingDirectory)

        if status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("⚠️  No changes to commit")
            return false
        }

        print("📝 Changes to commit:")
        print(status)

        // Commit
        print("💾 Committing with message: \(message)")
        try await Shell.run(["git", "commit", "-m", message], workingDirectory: workingDirectory)

        // Push
        print("📤 Pushing to origin/\(branch)...")
        try await Shell.run(["git", "push", "origin", branch], workingDirectory: workingDirectory)

        print("✅ Successfully committed and pushed")
        return true
    }

    func fetchLatest(branch: String, in workingDirectory: String? = nil) async throws {
        let gitArgs = gitCommand(for: workingDirectory)
        try await Shell.run(gitArgs + ["fetch", "origin", branch])
    }

    // MARK: - Worktree Operations

    func createWorktree(
        path: String,
        branch: String,
        baseBranch: String?,
        in repoRoot: String
    ) async throws {
        if let baseBranch = baseBranch {
            // Create new branch from base branch
            try await fetchLatest(branch: baseBranch, in: repoRoot)
            try await Shell.run([
                "git", "-C", repoRoot, "worktree", "add",
                path, "-b", branch, "origin/\(baseBranch)"
            ])
        } else {
            // Checkout existing branch
            try await Shell.run([
                "git", "-C", repoRoot, "fetch", "origin", branch
            ])
            try await Shell.run([
                "git", "-C", repoRoot, "worktree", "add",
                path, branch
            ])
        }
    }

    func removeWorktree(path: String, in repoRoot: String) async throws {
        try FileManager.default.removeItem(atPath: path)
        try await Shell.run(["git", "-C", repoRoot, "worktree", "prune"])
    }

    // MARK: - Helpers

    private func gitCommand(for workingDirectory: String?) -> [String] {
        if let dir = workingDirectory {
            return ["git", "-C", dir]
        }
        return ["git"]
    }

    private func extractPRNumber(from url: String) -> Int? {
        // URL format: https://github.com/owner/repo/pull/123
        guard let lastComponent = url.split(separator: "/").last,
              let number = Int(lastComponent) else {
            return nil
        }
        return number
    }
}

// MARK: - Shell Helper

/// Centralized shell command execution
enum Shell {
    @discardableResult
    static func run(_ args: String...) async throws -> String {
        try await run(args)
    }

    @discardableResult
    static func run(_ args: [String], streamOutput: Bool = false, workingDirectory: String? = nil) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args

        // Set working directory if provided
        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        if streamOutput {
            // Stream output directly to stdout/stderr for real-time feedback
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw AutomationError.shellCommandFailed("Command failed with status \(process.terminationStatus)")
            }

            // When streaming, we don't capture output
            return ""
        } else {
            // Original behavior: capture output without streaming
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw AutomationError.shellCommandFailed(errorOutput)
            }

            return String(data: outputData, encoding: .utf8) ?? ""
        }
    }

    /// Run a command in a specific directory
    @discardableResult
    static func runInDirectory(_ directory: String, command: String, streamOutput: Bool = false) async throws -> String {
        // Parse command string into command and args
        // This is a simple split - for complex commands with quotes, use the array version
        let components = command.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard !components.isEmpty else {
            throw AutomationError.shellCommandFailed("Empty command")
        }

        let cmd = String(components[0])
        let args = components.count > 1 ? [String(components[1])] : []

        return try await run([cmd] + args, streamOutput: streamOutput, workingDirectory: directory)
    }

    /// Run a command with args in a specific directory
    @discardableResult
    static func runInDirectory(_ directory: String, args: [String], streamOutput: Bool = false) async throws -> String {
        try await run(args, streamOutput: streamOutput, workingDirectory: directory)
    }
}
