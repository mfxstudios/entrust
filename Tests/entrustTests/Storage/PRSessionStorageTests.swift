import Testing
import Foundation
@testable import entrust

/// BDD-style tests for PRSessionStorage
@Suite("PRSessionStorage Tests")
struct PRSessionStorageTests {

    // MARK: - PRSessionInfo Tests

    @Suite("Given PR session info")
    struct PRSessionInfoTests {

        @Test("When creating with all fields, Then all properties are set")
        func createWithAllFields() {
            let createdAt = Date()
            let sessionInfo = PRSessionInfo(
                sessionId: "session-abc123",
                ticketId: "JIRA-456",
                branch: "feature/JIRA-456",
                createdAt: createdAt,
                skipTests: true,
                lastProcessedComments: [101, 102, 103]
            )

            #expect(sessionInfo.sessionId == "session-abc123")
            #expect(sessionInfo.ticketId == "JIRA-456")
            #expect(sessionInfo.branch == "feature/JIRA-456")
            #expect(sessionInfo.createdAt == createdAt)
            #expect(sessionInfo.skipTests == true)
            #expect(sessionInfo.lastProcessedComments == [101, 102, 103])
        }

        @Test("When creating with defaults, Then defaults are applied")
        func createWithDefaults() {
            let sessionInfo = PRSessionInfo(
                sessionId: "session-xyz",
                ticketId: "LIN-789",
                branch: "feature/LIN-789"
            )

            #expect(sessionInfo.sessionId == "session-xyz")
            #expect(sessionInfo.ticketId == "LIN-789")
            #expect(sessionInfo.branch == "feature/LIN-789")
            #expect(sessionInfo.skipTests == false)
            #expect(sessionInfo.lastProcessedComments.isEmpty)
        }

        @Test("When mutating sessionId, Then it can be updated")
        func mutateSessionId() {
            var sessionInfo = PRSessionInfo(
                sessionId: "old-session",
                ticketId: "JIRA-123",
                branch: "feature/test"
            )

            sessionInfo.sessionId = "new-session"
            #expect(sessionInfo.sessionId == "new-session")
        }

        @Test("When mutating lastProcessedComments, Then it can be updated")
        func mutateLastProcessedComments() {
            var sessionInfo = PRSessionInfo(
                sessionId: "session-123",
                ticketId: "JIRA-456",
                branch: "feature/test",
                lastProcessedComments: [1, 2]
            )

            sessionInfo.lastProcessedComments.append(3)
            #expect(sessionInfo.lastProcessedComments == [1, 2, 3])
        }
    }

    // MARK: - Session ID Extraction Tests

    @Suite("Given PR descriptions with session IDs")
    struct SessionExtractionTests {

        @Test("When PR has HTML comment with session ID, Then it is extracted")
        func extractFromHTMLComment() {
            let storage = PRSessionStorage()
            let description = """
            ## Summary
            This PR implements a new feature

            ## Changes
            - Added new functionality
            - Fixed bugs

            <!-- entrust-session: session-abc123def456 -->
            """

            let sessionId = storage.extractSessionFromPRDescription(description)
            #expect(sessionId == "session-abc123def456")
        }

        @Test("When PR has HTML comment with extra whitespace, Then it is extracted")
        func extractWithWhitespace() {
            let storage = PRSessionStorage()
            let description = "Some content\n<!--  entrust-session:  session-xyz789  -->"

            let sessionId = storage.extractSessionFromPRDescription(description)
            #expect(sessionId == "session-xyz789")
        }

        @Test("When PR has no session comment, Then nil is returned")
        func extractWhenMissing() {
            let storage = PRSessionStorage()
            let description = "Just a regular PR description"

            let sessionId = storage.extractSessionFromPRDescription(description)
            #expect(sessionId == nil)
        }

        @Test("When PR has malformed comment, Then nil is returned")
        func extractMalformed() {
            let storage = PRSessionStorage()
            let description = "<!-- entrust-session -->"

            let sessionId = storage.extractSessionFromPRDescription(description)
            #expect(sessionId == nil)
        }
    }

    // MARK: - Footer Generation Tests

    @Suite("Given session IDs for PR descriptions")
    struct FooterGenerationTests {

        @Test("When generating footer, Then HTML comment is created")
        func generateFooter() {
            let footer = PRSessionStorage.generatePRDescriptionFooter(sessionId: "session-abc123")

            #expect(footer.contains("<!-- entrust-session: session-abc123 -->"))
            #expect(footer.hasPrefix("\n\n"))
        }

        @Test("When generating footer with long session ID, Then it is included")
        func generateWithLongSessionId() {
            let sessionId = "session-very-long-id-with-many-characters-1234567890"
            let footer = PRSessionStorage.generatePRDescriptionFooter(sessionId: sessionId)

            #expect(footer.contains(sessionId))
        }
    }
}
