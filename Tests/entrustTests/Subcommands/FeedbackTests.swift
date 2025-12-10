import Testing
import Foundation
@testable import entrust

/// BDD-style tests for Feedback command logic
@Suite("Feedback Command Tests")
struct FeedbackTests {

    // MARK: - Comment Filtering Tests

    @Suite("Given PR comments with different triggers")
    struct CommentFilteringTests {

        @Test("When comment is from Request Changes review, Then it is actionable")
        func requestChangesComment() {
            let comment = PRComment(
                id: 1,
                body: "This needs improvement",
                author: "reviewer",
                path: "src/File.swift",
                line: 10,
                isFromRequestChangesReview: true
            )

            let isActionable = FeedbackTests.shouldProcessComment(comment, excluding: [])
            #expect(isActionable == true)
        }

        @Test("When comment has bold entrust trigger, Then it is actionable")
        func boldEntrustTrigger() {
            let comment = PRComment(
                id: 2,
                body: "**entrust** please add tests here",
                author: "reviewer",
                path: nil,
                line: nil,
                isFromRequestChangesReview: false
            )

            let isActionable = FeedbackTests.shouldProcessComment(comment, excluding: [])
            #expect(isActionable == true)
        }

        @Test("When comment has entrust: prefix, Then it is actionable")
        func colonPrefixTrigger() {
            let comment = PRComment(
                id: 3,
                body: "entrust: refactor this function",
                author: "reviewer",
                path: "src/Service.swift",
                line: 25,
                isFromRequestChangesReview: false
            )

            let isActionable = FeedbackTests.shouldProcessComment(comment, excluding: [])
            #expect(isActionable == true)
        }

        @Test("When comment has uppercase ENTRUST, Then it is actionable")
        func uppercaseEntrustTrigger() {
            let comment = PRComment(
                id: 4,
                body: "**ENTRUST** fix this issue",
                author: "reviewer",
                path: nil,
                line: nil,
                isFromRequestChangesReview: false
            )

            let isActionable = FeedbackTests.shouldProcessComment(comment, excluding: [])
            #expect(isActionable == true)
        }

        @Test("When comment is general without trigger, Then it is not actionable")
        func generalComment() {
            let comment = PRComment(
                id: 5,
                body: "Looks good to me!",
                author: "reviewer",
                path: nil,
                line: nil,
                isFromRequestChangesReview: false
            )

            let isActionable = FeedbackTests.shouldProcessComment(comment, excluding: [])
            #expect(isActionable == false)
        }

        @Test("When comment was already processed, Then it is not actionable")
        func alreadyProcessed() {
            let comment = PRComment(
                id: 6,
                body: "**entrust** please fix",
                author: "reviewer",
                path: nil,
                line: nil,
                isFromRequestChangesReview: false
            )

            let isActionable = FeedbackTests.shouldProcessComment(comment, excluding: [6])
            #expect(isActionable == false)
        }

        @Test("When comment has entrust in middle of text, Then it is actionable")
        func entrustInMiddle() {
            let comment = PRComment(
                id: 7,
                body: "I think **entrust** should handle this differently",
                author: "reviewer",
                path: nil,
                line: nil,
                isFromRequestChangesReview: false
            )

            let isActionable = FeedbackTests.shouldProcessComment(comment, excluding: [])
            #expect(isActionable == true)
        }
    }

    // MARK: - URL Parsing Tests

    @Suite("Given PR identifiers")
    struct URLParsingTests {

        @Test("When full GitHub URL is provided, Then PR number is extracted")
        func parseFullURL() {
            let url = "https://github.com/owner/repo/pull/456"
            let number = FeedbackTests.extractPRNumber(from: url)

            #expect(number == 456)
        }

        @Test("When URL has trailing slash, Then PR number is extracted")
        func parseURLWithTrailingSlash() {
            let url = "https://github.com/owner/repo/pull/789/"
            let number = FeedbackTests.extractPRNumber(from: url)

            #expect(number == 789)
        }

        @Test("When URL is invalid, Then nil is returned")
        func parseInvalidURL() {
            let url = "https://github.com/owner/repo/issues/123"
            let number = FeedbackTests.extractPRNumber(from: url)

            #expect(number == nil)
        }
    }

    // MARK: - Repo Path Extraction Tests

    @Suite("Given git remote URLs")
    struct RepoPathExtractionTests {

        @Test("When SSH URL is provided, Then repo path is extracted")
        func extractFromSSH() {
            let remoteURL = "git@github.com:owner/repo.git"
            let path = FeedbackTests.extractRepoPath(from: remoteURL)

            #expect(path == "owner/repo")
        }

        @Test("When HTTPS URL is provided, Then repo path is extracted")
        func extractFromHTTPS() {
            let remoteURL = "https://github.com/owner/repo.git"
            let path = FeedbackTests.extractRepoPath(from: remoteURL)

            #expect(path == "owner/repo")
        }

        @Test("When URL has no .git extension, Then repo path is extracted")
        func extractWithoutGitExtension() {
            let remoteURL = "https://github.com/owner/repo"
            let path = FeedbackTests.extractRepoPath(from: remoteURL)

            #expect(path == "owner/repo")
        }

        @Test("When URL is invalid, Then nil is returned")
        func extractFromInvalid() {
            let remoteURL = "invalid-url"
            let path = FeedbackTests.extractRepoPath(from: remoteURL)

            #expect(path == nil)
        }
    }

    // MARK: - Ticket ID Extraction Tests

    @Suite("Given PR titles with ticket IDs")
    struct TicketIDExtractionTests {

        @Test("When title has JIRA ticket, Then it is extracted")
        func extractJIRATicket() {
            let title = "[JIRA-123] Fix authentication bug"
            let ticketID = FeedbackTests.extractTicketID(from: title)

            #expect(ticketID == "JIRA-123")
        }

        @Test("When title has Linear ticket, Then it is extracted")
        func extractLinearTicket() {
            let title = "[LIN-456] Add new feature"
            let ticketID = FeedbackTests.extractTicketID(from: title)

            #expect(ticketID == "LIN-456")
        }

        @Test("When title has no ticket, Then nil is returned")
        func extractNoTicket() {
            let title = "Fix bug in authentication"
            let ticketID = FeedbackTests.extractTicketID(from: title)

            #expect(ticketID == nil)
        }

        @Test("When title has ticket in middle, Then it is extracted")
        func extractTicketInMiddle() {
            let title = "Some prefix [PROJ-789] with more text"
            let ticketID = FeedbackTests.extractTicketID(from: title)

            #expect(ticketID == "PROJ-789")
        }
    }

    // MARK: - Helper Functions (mirroring Feedback command logic)

    static func shouldProcessComment(_ comment: PRComment, excluding processedIDs: [Int]) -> Bool {
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

    static func extractPRNumber(from url: String) -> Int? {
        let pattern = "/pull/(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let range = Range(match.range(at: 1), in: url) else {
            return nil
        }
        return Int(url[range])
    }

    static func extractRepoPath(from remoteURL: String) -> String? {
        if remoteURL.starts(with: "git@github.com:") {
            let path = remoteURL.replacingOccurrences(of: "git@github.com:", with: "")
            return path.replacingOccurrences(of: ".git", with: "")
        } else if remoteURL.starts(with: "https://github.com/") {
            let path = remoteURL.replacingOccurrences(of: "https://github.com/", with: "")
            return path.replacingOccurrences(of: ".git", with: "")
        }
        return nil
    }

    static func extractTicketID(from title: String) -> String? {
        let pattern = "\\[([A-Z]+-\\d+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return String(title[range])
    }
}
