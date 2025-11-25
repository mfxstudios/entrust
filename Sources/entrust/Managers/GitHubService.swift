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

/// Protocol for GitHub operations - enables testing and alternative implementations
protocol GitHubServiceProtocol: Sendable {
    var configuration: GitHubConfiguration { get }

    func createPullRequest(_ params: PullRequestParams) async throws -> PullRequestResult
    func createBranch(name: String, from baseBranch: String, in workingDirectory: String?) async throws
    func commitAndPush(message: String, branch: String, in workingDirectory: String?) async throws -> Bool
    func fetchLatest(branch: String, in workingDirectory: String?) async throws
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

    // MARK: - Branch Operations

    func createBranch(name: String, from baseBranch: String, in workingDirectory: String? = nil) async throws {
        let gitArgs = gitCommand(for: workingDirectory)

        try await Shell.run(gitArgs + ["checkout", baseBranch])
        try await Shell.run(gitArgs + ["pull", "origin", baseBranch])
        try await Shell.run(gitArgs + ["checkout", "-b", name])
    }

    func commitAndPush(message: String, branch: String, in workingDirectory: String? = nil) async throws -> Bool {
        let gitArgs = gitCommand(for: workingDirectory)

        // Stage all changes
        try await Shell.run(gitArgs + ["add", "."])

        // Check if there are any changes to commit
        let status = try await Shell.run(gitArgs + ["status", "--porcelain"])
        if status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("⚠️  No changes to commit")
            return false
        }

        // Commit and push
        try await Shell.run(gitArgs + ["commit", "-m", message])
        try await Shell.run(gitArgs + ["push", "origin", branch])
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
        baseBranch: String,
        in repoRoot: String
    ) async throws {
        try await fetchLatest(branch: baseBranch, in: repoRoot)
        try await Shell.run([
            "git", "-C", repoRoot, "worktree", "add",
            path, "-b", branch, "origin/\(baseBranch)"
        ])
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
            // Simply inherit parent's stdout/stderr for real-time display
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw AutomationError.shellCommandFailed("Command failed with status \(process.terminationStatus)")
            }

            // When streaming, we don't capture output, so return empty string
            // The caller gets real-time feedback instead
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
