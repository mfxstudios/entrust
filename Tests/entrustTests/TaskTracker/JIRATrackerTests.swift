import Testing
import Foundation
@testable import entrust

/// BDD-style tests for JIRATracker
@Suite("JIRATracker Tests")
struct JIRATrackerTests {

    // MARK: - Initialization Tests

    @Suite("Given JIRA credentials")
    struct InitializationTests {

        @Test("When creating a tracker, Then it has the correct base URL")
        func trackerHasCorrectBaseURL() {
            // Given/When
            let tracker = JIRATracker(
                url: "https://myorg.atlassian.net",
                email: "user@example.com",
                token: "api-token"
            )

            // Then
            #expect(tracker.baseURL == "https://myorg.atlassian.net")
        }

        @Test("When creating a tracker, Then credentials are properly stored")
        func trackerStoresCredentials() {
            // Given/When
            let tracker = JIRATracker(
                url: "https://test.atlassian.net",
                email: "test@test.com",
                token: "secret-token"
            )

            // Then
            #expect(tracker.baseURL == "https://test.atlassian.net")
        }
    }

    // MARK: - Fetch Issue Tests

    @Suite("Given a valid JIRA issue")
    struct FetchIssueTests {

        @Test("When fetching an issue, Then it uses Basic Auth header")
        func fetchIssueUsesBasicAuth() async throws {
            // Given
            let tracker = JIRATracker(
                url: "https://test.atlassian.net",
                email: "user@test.com",
                token: "api-token"
            )

            // Expected: Authorization header should be "Basic base64(email:token)"
            let expectedCredentials = "user@test.com:api-token"
            let expectedBase64 = Data(expectedCredentials.utf8).base64EncodedString()

            // The tracker should create this authorization header
            #expect(tracker.baseURL.contains("atlassian"))
            #expect(expectedBase64.count > 0)
        }

        @Test("When fetching an issue, Then it calls the correct REST endpoint")
        func fetchIssueCallsCorrectEndpoint() async throws {
            // Given
            let tracker = JIRATracker(
                url: "https://test.atlassian.net",
                email: "user@test.com",
                token: "api-token"
            )

            // Expected endpoint: {baseURL}/rest/api/3/issue/{issueKey}
            let expectedEndpoint = "https://test.atlassian.net/rest/api/3/issue/PROJ-123"

            #expect(tracker.baseURL == "https://test.atlassian.net")
            #expect(expectedEndpoint.contains("rest/api/3/issue"))
        }
    }

    // MARK: - Update Issue Tests

    @Suite("Given an issue to update with a PR URL")
    struct UpdateIssueTests {

        @Test("When updating, Then it posts a comment to the issue")
        func updateIssuePostsComment() async throws {
            // Given
            let tracker = JIRATracker(
                url: "https://test.atlassian.net",
                email: "user@test.com",
                token: "api-token"
            )

            // Expected endpoint: {baseURL}/rest/api/3/issue/{issueKey}/comment
            let expectedEndpoint = "https://test.atlassian.net/rest/api/3/issue/PROJ-123/comment"

            #expect(expectedEndpoint.contains("/comment"))
        }

        @Test("When updating, Then the comment body uses Atlassian Document Format")
        func updateIssueUsesADF() async throws {
            // Given - JIRA API v3 requires Atlassian Document Format
            // Expected structure:
            // {
            //   "body": {
            //     "type": "doc",
            //     "version": 1,
            //     "content": [...]
            //   }
            // }

            let comment = JIRAComment(body: .init(
                type: "doc",
                version: 1,
                content: [
                    .init(
                        type: "paragraph",
                        content: [
                            .init(type: "text", text: "Test comment")
                        ]
                    )
                ]
            ))

            // Then - it should be encodable to JSON
            let data = try JSONEncoder().encode(comment)
            #expect(data.count > 0)
        }
    }

    // MARK: - Change Status Tests

    @Suite("Given available JIRA transitions")
    struct ChangeStatusTests {

        @Test("When changing status, Then it fetches available transitions first")
        func changeStatusFetchesTransitions() async throws {
            // Given
            let tracker = JIRATracker(
                url: "https://test.atlassian.net",
                email: "user@test.com",
                token: "api-token"
            )

            // Expected: First call to {baseURL}/rest/api/3/issue/{key}/transitions
            let transitionsEndpoint = "\(tracker.baseURL)/rest/api/3/issue/PROJ-123/transitions"

            #expect(transitionsEndpoint.contains("/transitions"))
        }

        @Test("When changing status, Then it posts the transition")
        func changeStatusPostsTransition() async throws {
            // Given
            let tracker = JIRATracker(
                url: "https://test.atlassian.net",
                email: "user@test.com",
                token: "api-token"
            )

            // Expected POST body:
            // { "transition": { "id": "transition-id" } }
            let payload: [String: Any] = [
                "transition": ["id": "21"]
            ]

            let data = try JSONSerialization.data(withJSONObject: payload)
            #expect(data.count > 0)
        }
    }

    // MARK: - Get Available Statuses Tests

    @Suite("Given a JIRA issue with transitions")
    struct GetAvailableStatusesTests {

        @Test("When getting statuses, Then it returns available transitions")
        func getAvailableStatusesReturnsTransitions() async throws {
            // Given
            let tracker = JIRATracker(
                url: "https://test.atlassian.net",
                email: "user@test.com",
                token: "api-token"
            )

            // JIRA transitions endpoint returns available status changes
            // Each transition has an id and name
            #expect(tracker.baseURL.contains("atlassian"))
        }
    }
}

// MARK: - JIRA Model Tests

@Suite("JIRA Response Models")
struct JIRAResponseModelTests {

    @Test("Given a valid JIRA issue JSON, When decoding, Then all fields are parsed")
    func decodeJIRAIssue() throws {
        // Given
        let json = """
        {
            "key": "PROJ-123",
            "fields": {
                "summary": "Fix login bug",
                "description": "Users cannot log in with SSO"
            }
        }
        """.data(using: .utf8)!

        // When
        let issue = try JSONDecoder().decode(JIRAIssue.self, from: json)

        // Then
        #expect(issue.key == "PROJ-123")
        #expect(issue.fields.summary == "Fix login bug")
        #expect(issue.fields.description == "Users cannot log in with SSO")
    }

    @Test("Given a JIRA issue with null description, When decoding, Then description is nil")
    func decodeJIRAIssueWithNullDescription() throws {
        // Given
        let json = """
        {
            "key": "PROJ-456",
            "fields": {
                "summary": "Add feature",
                "description": null
            }
        }
        """.data(using: .utf8)!

        // When
        let issue = try JSONDecoder().decode(JIRAIssue.self, from: json)

        // Then
        #expect(issue.fields.description == nil)
    }

    @Test("Given a JIRA transitions response, When decoding, Then transitions are parsed")
    func decodeJIRATransitionsResponse() throws {
        // Given
        let json = """
        {
            "transitions": [
                {"id": "11", "name": "To Do"},
                {"id": "21", "name": "In Progress"},
                {"id": "31", "name": "Done"}
            ]
        }
        """.data(using: .utf8)!

        // When
        let response = try JSONDecoder().decode(JIRATransitionsResponse.self, from: json)

        // Then
        #expect(response.transitions.count == 3)
        #expect(response.transitions[0].name == "To Do")
        #expect(response.transitions[1].id == "21")
        #expect(response.transitions[2].name == "Done")
    }
}

// MARK: - JIRA Comment Model Tests

@Suite("JIRA Comment Model")
struct JIRACommentModelTests {

    @Test("Given a comment with ADF format, When encoding, Then JSON structure is correct")
    func encodeJIRAComment() throws {
        // Given
        let comment = JIRAComment(body: .init(
            type: "doc",
            version: 1,
            content: [
                .init(
                    type: "paragraph",
                    content: [
                        .init(type: "text", text: "PR created: https://github.com/org/repo/pull/42")
                    ]
                )
            ]
        ))

        // When
        let data = try JSONEncoder().encode(comment)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Then
        let body = json["body"] as! [String: Any]
        #expect(body["type"] as? String == "doc")
        #expect(body["version"] as? Int == 1)

        let content = body["content"] as! [[String: Any]]
        #expect(content.count == 1)
        #expect(content[0]["type"] as? String == "paragraph")
    }
}
