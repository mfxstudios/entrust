import Testing
import Foundation
@testable import entrust

/// BDD-style tests for GitHubService
@Suite("GitHubService Tests")
struct GitHubServiceTests {

    // MARK: - Configuration Tests

    @Suite("Given GitHub configuration")
    struct ConfigurationTests {

        @Test("When creating with all fields, Then all properties are set")
        func createWithAllFields() {
            let config = GitHubConfiguration(
                repo: "owner/repo",
                baseBranch: "main",
                useGHCLI: true,
                token: "github_token",
                draft: true
            )

            #expect(config.repo == "owner/repo")
            #expect(config.baseBranch == "main")
            #expect(config.useGHCLI == true)
            #expect(config.token == "github_token")
            #expect(config.draft == true)
        }

        @Test("When creating with defaults, Then defaults are applied")
        func createWithDefaults() {
            let config = GitHubConfiguration(
                repo: "owner/repo",
                baseBranch: "develop"
            )

            #expect(config.repo == "owner/repo")
            #expect(config.baseBranch == "develop")
            #expect(config.useGHCLI == true)
            #expect(config.token == nil)
            #expect(config.draft == false)
        }
    }

    // MARK: - Pull Request Params Tests

    @Suite("Given pull request parameters")
    struct PullRequestParamsTests {

        @Test("When creating PR params, Then all fields are set")
        func createPRParams() {
            let params = PullRequestParams(
                title: "[TASK-123] Fix bug",
                body: "## Summary\nFixed the bug",
                branch: "feature/TASK-123",
                baseBranch: "main",
                draft: true
            )

            #expect(params.title == "[TASK-123] Fix bug")
            #expect(params.body.contains("Summary"))
            #expect(params.branch == "feature/TASK-123")
            #expect(params.baseBranch == "main")
            #expect(params.draft == true)
        }
    }

    // MARK: - Pull Request Result Tests

    @Suite("Given pull request results")
    struct PullRequestResultTests {

        @Test("When creating result with all fields, Then all are accessible")
        func createResultWithAllFields() {
            let result = PullRequestResult(
                url: "https://github.com/owner/repo/pull/42",
                number: 42
            )

            #expect(result.url == "https://github.com/owner/repo/pull/42")
            #expect(result.number == 42)
        }

        @Test("When creating result without number, Then number is nil")
        func createResultWithoutNumber() {
            let result = PullRequestResult(
                url: "https://github.com/owner/repo/pull/123",
                number: nil
            )

            #expect(result.url.contains("pull/123"))
            #expect(result.number == nil)
        }
    }

    // MARK: - GitHubService Tests

    @Suite("Given a GitHub service")
    struct GitHubServiceInstanceTests {

        @Test("When creating service, Then configuration is stored")
        func serviceStoresConfiguration() {
            let config = GitHubConfiguration(
                repo: "test/repo",
                baseBranch: "main",
                useGHCLI: false,
                token: "secret",
                draft: false
            )
            let service = GitHubService(configuration: config)

            #expect(service.configuration.repo == "test/repo")
            #expect(service.configuration.baseBranch == "main")
            #expect(service.configuration.useGHCLI == false)
        }

        @Test("When creating PR with API but no token, Then error is thrown")
        func createPRWithoutToken() async {
            let config = GitHubConfiguration(
                repo: "test/repo",
                baseBranch: "main",
                useGHCLI: false,
                token: nil
            )
            let service = GitHubService(configuration: config)

            let params = PullRequestParams(
                title: "Test PR",
                body: "Test body",
                branch: "feature/test",
                baseBranch: "main",
                draft: false
            )

            await #expect(throws: AutomationError.self) {
                try await service.createPullRequest(params)
            }
        }
    }

    // MARK: - PR and Comment Model Tests

    @Suite("Given pull request models")
    struct PullRequestModelTests {

        @Test("When creating PullRequest, Then all fields are set")
        func createPullRequest() {
            let pr = PullRequest(
                number: 42,
                title: "[JIRA-123] Fix bug",
                body: "This fixes the bug",
                headBranch: "feature/JIRA-123",
                baseBranch: "main",
                state: "open"
            )

            #expect(pr.number == 42)
            #expect(pr.title == "[JIRA-123] Fix bug")
            #expect(pr.body == "This fixes the bug")
            #expect(pr.headBranch == "feature/JIRA-123")
            #expect(pr.baseBranch == "main")
            #expect(pr.state == "open")
        }

        @Test("When creating PRComment from request changes review, Then flag is set")
        func createCommentFromRequestChanges() {
            let comment = PRComment(
                id: 101,
                body: "This needs to be fixed",
                author: "reviewer",
                path: "src/File.swift",
                line: 42,
                isFromRequestChangesReview: true
            )

            #expect(comment.id == 101)
            #expect(comment.body == "This needs to be fixed")
            #expect(comment.author == "reviewer")
            #expect(comment.path == "src/File.swift")
            #expect(comment.line == 42)
            #expect(comment.isFromRequestChangesReview == true)
        }

        @Test("When creating general comment, Then path and line are nil")
        func createGeneralComment() {
            let comment = PRComment(
                id: 202,
                body: "**entrust** please add tests",
                author: "reviewer",
                path: nil,
                line: nil,
                isFromRequestChangesReview: false
            )

            #expect(comment.id == 202)
            #expect(comment.body.contains("**entrust**"))
            #expect(comment.path == nil)
            #expect(comment.line == nil)
            #expect(comment.isFromRequestChangesReview == false)
        }
    }
}

// MARK: - Shell Tests

@Suite("Shell Tests")
struct ShellTests {

    @Test("When running valid command, Then output is returned")
    func runValidCommand() async throws {
        let output = try await Shell.run("echo", "hello")
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    }

    @Test("When running command with multiple args, Then all args are passed")
    func runWithMultipleArgs() async throws {
        let output = try await Shell.run(["echo", "hello", "world"])
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
    }

    @Test("When running invalid command, Then error is thrown")
    func runInvalidCommand() async {
        await #expect(throws: AutomationError.self) {
            try await Shell.run("nonexistent-command-12345")
        }
    }
}
