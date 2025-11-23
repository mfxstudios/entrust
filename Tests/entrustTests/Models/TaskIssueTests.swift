import Testing
import Foundation
@testable import entrust

/// BDD-style tests for TaskIssue model
@Suite("TaskIssue Model Tests")
struct TaskIssueTests {

    // MARK: - Initialization Tests

    @Suite("Given task issue data")
    struct InitializationTests {

        @Test("When creating with all fields, Then all properties are set correctly")
        func createWithAllFields() {
            // Given/When
            let issue = TaskIssue(
                id: "TASK-123",
                title: "Implement authentication",
                description: "Add OAuth2 support for user login"
            )

            // Then
            #expect(issue.id == "TASK-123")
            #expect(issue.title == "Implement authentication")
            #expect(issue.description == "Add OAuth2 support for user login")
        }

        @Test("When creating without description, Then description is nil")
        func createWithoutDescription() {
            // Given/When
            let issue = TaskIssue(
                id: "TASK-456",
                title: "Quick fix",
                description: nil
            )

            // Then
            #expect(issue.id == "TASK-456")
            #expect(issue.title == "Quick fix")
            #expect(issue.description == nil)
        }

        @Test("When creating with empty description, Then description is empty string")
        func createWithEmptyDescription() {
            // Given/When
            let issue = TaskIssue(
                id: "TASK-789",
                title: "Minor update",
                description: ""
            )

            // Then
            #expect(issue.description == "")
        }
    }

    // MARK: - Edge Cases

    @Suite("Given edge case inputs")
    struct EdgeCaseTests {

        @Test("When ID contains special characters, Then they are preserved")
        func idWithSpecialCharacters() {
            // Given/When
            let issue = TaskIssue(
                id: "PROJ-123/sub-task",
                title: "Sub task",
                description: nil
            )

            // Then
            #expect(issue.id == "PROJ-123/sub-task")
        }

        @Test("When title contains unicode, Then it is preserved")
        func titleWithUnicode() {
            // Given/When
            let issue = TaskIssue(
                id: "TASK-1",
                title: "Fix 日本語 support 🎉",
                description: "Handle unicode correctly"
            )

            // Then
            #expect(issue.title == "Fix 日本語 support 🎉")
        }

        @Test("When description is multiline, Then newlines are preserved")
        func multilineDescription() {
            // Given
            let multilineDesc = """
            Line 1
            Line 2
            Line 3
            """

            // When
            let issue = TaskIssue(
                id: "TASK-1",
                title: "Test",
                description: multilineDesc
            )

            // Then
            #expect(issue.description?.contains("\n") == true)
            #expect(issue.description?.components(separatedBy: "\n").count == 3)
        }
    }
}

/// BDD-style tests for IssueStatus model
@Suite("IssueStatus Model Tests")
struct IssueStatusTests {

    // MARK: - Initialization Tests

    @Suite("Given status data")
    struct InitializationTests {

        @Test("When creating with all fields, Then all properties are set correctly")
        func createWithAllFields() {
            // Given/When
            let status = IssueStatus(
                id: "status-1",
                name: "In Progress",
                description: "Work is currently being done"
            )

            // Then
            #expect(status.id == "status-1")
            #expect(status.name == "In Progress")
            #expect(status.description == "Work is currently being done")
        }

        @Test("When creating without description, Then description is nil")
        func createWithoutDescription() {
            // Given/When
            let status = IssueStatus(
                id: "status-2",
                name: "Done",
                description: nil
            )

            // Then
            #expect(status.id == "status-2")
            #expect(status.name == "Done")
            #expect(status.description == nil)
        }
    }

    // MARK: - Common Workflow Statuses

    @Suite("Given common workflow statuses")
    struct WorkflowStatusTests {

        @Test("When creating standard Kanban statuses, Then they have expected names")
        func standardKanbanStatuses() {
            // Given/When
            let statuses = [
                IssueStatus(id: "1", name: "Backlog", description: nil),
                IssueStatus(id: "2", name: "To Do", description: nil),
                IssueStatus(id: "3", name: "In Progress", description: nil),
                IssueStatus(id: "4", name: "In Review", description: nil),
                IssueStatus(id: "5", name: "Done", description: nil)
            ]

            // Then
            #expect(statuses.count == 5)
            #expect(statuses.map { $0.name } == ["Backlog", "To Do", "In Progress", "In Review", "Done"])
        }

        @Test("When comparing status names case-insensitively, Then they match")
        func caseInsensitiveComparison() {
            // Given
            let status = IssueStatus(id: "1", name: "In Progress", description: nil)
            let searchTerm = "in progress"

            // When
            let matches = status.name.lowercased() == searchTerm.lowercased()

            // Then
            #expect(matches)
        }
    }
}

/// BDD-style tests for AutomationError
@Suite("AutomationError Tests")
struct AutomationErrorTests {

    // MARK: - Error Description Tests

    @Suite("Given automation errors")
    struct ErrorDescriptionTests {

        @Test("When error is configurationNotFound, Then description mentions setup")
        func configurationNotFoundDescription() {
            // Given
            let error = AutomationError.configurationNotFound

            // When
            let description = error.errorDescription

            // Then
            #expect(description?.contains("setup") == true)
        }

        @Test("When error is issueNotFound, Then description is informative")
        func issueNotFoundDescription() {
            // Given
            let error = AutomationError.issueNotFound

            // When
            let description = error.errorDescription

            // Then
            #expect(description?.contains("not found") == true)
        }

        @Test("When error is invalidStatus, Then it lists available statuses")
        func invalidStatusDescription() {
            // Given
            let error = AutomationError.invalidStatus(
                "InvalidStatus",
                available: ["Backlog", "In Progress", "Done"]
            )

            // When
            let description = error.errorDescription

            // Then
            #expect(description?.contains("InvalidStatus") == true)
            #expect(description?.contains("Backlog") == true)
            #expect(description?.contains("Done") == true)
        }

        @Test("When error is shellCommandFailed, Then it includes the output")
        func shellCommandFailedDescription() {
            // Given
            let error = AutomationError.shellCommandFailed("Permission denied")

            // When
            let description = error.errorDescription

            // Then
            #expect(description?.contains("Permission denied") == true)
        }

        @Test("When error is remindersAccessDenied, Then it mentions System Settings")
        func remindersAccessDeniedDescription() {
            // Given
            let error = AutomationError.remindersAccessDenied

            // When
            let description = error.errorDescription

            // Then
            #expect(description?.contains("System Settings") == true)
        }

        @Test("When error is remindersListNotFound, Then it includes list name")
        func remindersListNotFoundDescription() {
            // Given
            let error = AutomationError.remindersListNotFound("My Tasks")

            // When
            let description = error.errorDescription

            // Then
            #expect(description?.contains("My Tasks") == true)
        }
    }

    // MARK: - Error Types

    @Suite("Given different error categories")
    struct ErrorCategoryTests {

        @Test("When checking tracker errors, Then they conform to LocalizedError")
        func trackerErrorsAreLocalizedErrors() {
            // Given
            let errors: [AutomationError] = [
                .issueFetchFailed,
                .issueUpdateFailed,
                .issueNotFound,
                .statusFetchFailed,
                .statusChangeFailed
            ]

            // Then
            for error in errors {
                #expect(error.errorDescription != nil)
            }
        }

        @Test("When checking credential errors, Then they mention keychain")
        func credentialErrorsMentionKeychain() {
            // Given
            let saveError = AutomationError.keychainSaveFailed("test-key")
            let loadError = AutomationError.keychainLoadFailed("test-key")
            let deleteError = AutomationError.keychainDeleteFailed("test-key")

            // Then
            #expect(saveError.errorDescription?.lowercased().contains("keychain") == true)
            #expect(loadError.errorDescription?.lowercased().contains("keychain") == true)
            #expect(deleteError.errorDescription?.lowercased().contains("keychain") == true)
        }
    }
}
