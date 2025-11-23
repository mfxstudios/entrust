import Testing
import Foundation
@testable import entrust

/// BDD-style tests for TaskTracker protocol behavior
@Suite("TaskTracker Protocol Tests")
struct TaskTrackerTests {

    // MARK: - Fetch Issue Tests

    @Suite("Given an issue exists in the tracker")
    struct FetchIssueTests {

        @Test("When fetching by ID, Then it returns the correct issue")
        func fetchExistingIssue() async throws {
            // Given
            let tracker = MockTaskTracker()
            await tracker.givenIssueExists(
                id: "TASK-123",
                title: "Implement login feature",
                description: "Add OAuth2 login support"
            )

            // When
            let issue = try await tracker.fetchIssue("TASK-123")

            // Then
            #expect(issue.id == "TASK-123")
            #expect(issue.title == "Implement login feature")
            #expect(issue.description == "Add OAuth2 login support")
        }

        @Test("When fetching by ID, Then the fetch is recorded")
        func fetchIssueIsRecorded() async throws {
            // Given
            let tracker = MockTaskTracker()
            await tracker.givenIssueExists(id: "TASK-456", title: "Test", description: nil)

            // When
            _ = try await tracker.fetchIssue("TASK-456")

            // Then
            let wasCalled = await tracker.verifyFetchIssueWasCalled(with: "TASK-456")
            #expect(wasCalled)
        }
    }

    @Suite("Given an issue does not exist")
    struct FetchNonExistentIssueTests {

        @Test("When fetching by ID, Then it throws issueNotFound")
        func fetchNonExistentIssue() async {
            // Given
            let tracker = MockTaskTracker()

            // When/Then
            await #expect(throws: AutomationError.self) {
                try await tracker.fetchIssue("NONEXISTENT-999")
            }
        }
    }

    @Suite("Given the tracker is failing")
    struct FetchIssueFailureTests {

        @Test("When fetching an issue, Then it throws issueFetchFailed")
        func fetchIssueWhenTrackerFails() async {
            // Given
            let tracker = MockTaskTracker()
            await tracker.givenIssueExists(id: "TASK-123", title: "Test", description: nil)
            await tracker.setShouldFailFetchIssue(true)

            // When/Then
            await #expect(throws: AutomationError.self) {
                try await tracker.fetchIssue("TASK-123")
            }
        }
    }

    // MARK: - Update Issue Tests

    @Suite("Given an issue exists and needs updating")
    struct UpdateIssueTests {

        @Test("When updating with a PR URL, Then the update is recorded")
        func updateIssueWithPRURL() async throws {
            // Given
            let tracker = MockTaskTracker()
            await tracker.givenIssueExists(id: "TASK-123", title: "Feature", description: nil)

            // When
            try await tracker.updateIssue("TASK-123", prURL: "https://github.com/org/repo/pull/42")

            // Then
            let wasCalled = await tracker.verifyUpdateIssueWasCalled(
                with: "TASK-123",
                prURL: "https://github.com/org/repo/pull/42"
            )
            #expect(wasCalled)
        }

        @Test("When updating with a PR URL, Then a comment is added")
        func updateIssueAddsComment() async throws {
            // Given
            let tracker = MockTaskTracker()
            await tracker.givenIssueExists(id: "TASK-123", title: "Feature", description: nil)

            // When
            try await tracker.updateIssue("TASK-123", prURL: "https://github.com/org/repo/pull/42")

            // Then
            let comments = await tracker.getComments(for: "TASK-123")
            #expect(comments.contains { $0.contains("https://github.com/org/repo/pull/42") })
        }
    }

    @Suite("Given updating an issue fails")
    struct UpdateIssueFailureTests {

        @Test("When the tracker fails, Then it throws issueUpdateFailed")
        func updateIssueWhenTrackerFails() async {
            // Given
            let tracker = MockTaskTracker()
            await tracker.givenIssueExists(id: "TASK-123", title: "Feature", description: nil)
            await tracker.setShouldFailUpdateIssue(true)

            // When/Then
            await #expect(throws: AutomationError.self) {
                try await tracker.updateIssue("TASK-123", prURL: "https://example.com/pr/1")
            }
        }
    }

    // MARK: - Change Status Tests

    @Suite("Given valid statuses are available")
    struct ChangeStatusTests {

        @Test("When changing to a valid status, Then the status is updated")
        func changeToValidStatus() async throws {
            // Given
            let tracker = MockTaskTracker()
            await tracker.givenIssueExists(id: "TASK-123", title: "Feature", description: nil)
            await tracker.givenAvailableStatuses(["Backlog", "In Progress", "In Review", "Done"])
            await tracker.givenIssueHasStatus("TASK-123", status: "Backlog")

            // When
            try await tracker.changeStatus("TASK-123", to: "In Progress")

            // Then
            let currentStatus = await tracker.getStatus(for: "TASK-123")
            #expect(currentStatus == "In Progress")
        }

        @Test("When changing status, Then the change is recorded")
        func changeStatusIsRecorded() async throws {
            // Given
            let tracker = MockTaskTracker()
            await tracker.givenIssueExists(id: "TASK-123", title: "Feature", description: nil)
            await tracker.givenAvailableStatuses(["Backlog", "In Progress", "Done"])

            // When
            try await tracker.changeStatus("TASK-123", to: "Done")

            // Then
            let wasCalled = await tracker.verifyChangeStatusWasCalled(with: "TASK-123", to: "Done")
            #expect(wasCalled)
        }

        @Test("When changing status with different case, Then it still works")
        func changeStatusIsCaseInsensitive() async throws {
            // Given
            let tracker = MockTaskTracker()
            await tracker.givenIssueExists(id: "TASK-123", title: "Feature", description: nil)
            await tracker.givenAvailableStatuses(["In Progress"])

            // When
            try await tracker.changeStatus("TASK-123", to: "in progress")

            // Then
            let currentStatus = await tracker.getStatus(for: "TASK-123")
            #expect(currentStatus == "in progress")
        }
    }

    @Suite("Given an invalid status is requested")
    struct ChangeStatusInvalidTests {

        @Test("When changing to an invalid status, Then it throws invalidStatus")
        func changeToInvalidStatus() async {
            // Given
            let tracker = MockTaskTracker()
            await tracker.givenIssueExists(id: "TASK-123", title: "Feature", description: nil)
            await tracker.givenAvailableStatuses(["Backlog", "In Progress", "Done"])

            // When/Then
            await #expect(throws: AutomationError.self) {
                try await tracker.changeStatus("TASK-123", to: "Invalid Status")
            }
        }
    }

    // MARK: - Get Available Statuses Tests

    @Suite("Given statuses are configured")
    struct GetAvailableStatusesTests {

        @Test("When getting available statuses, Then all statuses are returned")
        func getAvailableStatuses() async throws {
            // Given
            let tracker = MockTaskTracker()
            let expectedStatuses = [
                IssueStatus(id: "1", name: "Backlog", description: "Work not started"),
                IssueStatus(id: "2", name: "In Progress", description: "Currently working"),
                IssueStatus(id: "3", name: "Done", description: "Completed")
            ]
            await tracker.givenAvailableStatuses(expectedStatuses)

            // When
            let statuses = try await tracker.getAvailableStatuses("TASK-123")

            // Then
            #expect(statuses.count == 3)
            #expect(statuses.map { $0.name } == ["Backlog", "In Progress", "Done"])
        }

        @Test("When getting statuses, Then the call is recorded")
        func getAvailableStatusesIsRecorded() async throws {
            // Given
            let tracker = MockTaskTracker()
            await tracker.givenAvailableStatuses(["Todo", "Done"])

            // When
            _ = try await tracker.getAvailableStatuses("TASK-456")

            // Then
            let calls = await tracker.getAvailableStatusesCalls
            #expect(calls.contains("TASK-456"))
        }
    }
}

// MARK: - Helper Extension for MockTaskTracker

extension MockTaskTracker {
    func setShouldFailFetchIssue(_ value: Bool) {
        shouldFailFetchIssue = value
    }

    func setShouldFailUpdateIssue(_ value: Bool) {
        shouldFailUpdateIssue = value
    }

    func setShouldFailChangeStatus(_ value: Bool) {
        shouldFailChangeStatus = value
    }
}
