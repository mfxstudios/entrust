//
//  StringGitBranchTests.swift
//  entrustTests
//
//  Created by Prince Ugwuh on 11/22/25.
//

import Testing
import Foundation
@testable import entrust

/// BDD-style tests for String+GitBranch extension
@Suite("String+GitBranch Tests")
struct StringGitBranchTests {

    @Suite("Given strings with spaces")
    struct SpaceHandlingTests {

        @Test("When string has spaces, Then they are replaced with hyphens")
        func spacesReplacedWithHyphens() {
            let input = "Fix login bug"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-login-bug")
        }

        @Test("When string has multiple consecutive spaces, Then they become single hyphen")
        func multipleSpacesCollapsed() {
            let input = "Fix   login    bug"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-login-bug")
        }

        @Test("When string has leading/trailing spaces, Then they are trimmed")
        func leadingTrailingSpacesTrimmed() {
            let input = "  Fix login bug  "
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-login-bug")
        }
    }

    @Suite("Given strings with invalid characters")
    struct InvalidCharacterTests {

        @Test("When string has colons, Then they are removed")
        func colonsRemoved() {
            let input = "TASK-123: Fix bug"
            let result = input.sanitizedForBranchName()
            #expect(result == "task-123-fix-bug")
        }

        @Test("When string has question marks, Then they are removed")
        func questionMarksRemoved() {
            let input = "Fix bug?"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-bug")
        }

        @Test("When string has asterisks, Then they are removed")
        func asterisksRemoved() {
            let input = "Fix *important* bug"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-important-bug")
        }

        @Test("When string has brackets, Then they are removed")
        func bracketsRemoved() {
            let input = "Fix [critical] bug"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-critical-bug")
        }

        @Test("When string has tildes, Then they are replaced with hyphens")
        func tildesRemoved() {
            let input = "Fix~bug"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-bug")
        }

        @Test("When string has carets, Then they are replaced with hyphens")
        func caretsRemoved() {
            let input = "Fix^bug"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-bug")
        }
    }

    @Suite("Given strings with dots and slashes")
    struct DotsAndSlashesTests {

        @Test("When string has consecutive dots, Then they become single dot")
        func consecutiveDotsCollapsed() {
            let input = "Fix..bug"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix.bug")
        }

        @Test("When string ends with .lock, Then .lock is removed")
        func lockSuffixRemoved() {
            let input = "feature.lock"
            let result = input.sanitizedForBranchName()
            #expect(result == "feature")
        }

        @Test("When string has leading slashes, Then they are removed")
        func leadingSlashesRemoved() {
            let input = "/fix-bug"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-bug")
        }

        @Test("When string has trailing slashes, Then they are removed")
        func trailingSlashesRemoved() {
            let input = "fix-bug/"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-bug")
        }

        @Test("When string has leading dots, Then they are removed")
        func leadingDotsRemoved() {
            let input = ".fix-bug"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-bug")
        }

        @Test("When string has trailing dots, Then they are removed")
        func trailingDotsRemoved() {
            let input = "fix-bug."
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-bug")
        }
    }

    @Suite("Given strings with case variations")
    struct CaseHandlingTests {

        @Test("When string is uppercase, Then it becomes lowercase")
        func uppercaseToLowercase() {
            let input = "FIX-LOGIN-BUG"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-login-bug")
        }

        @Test("When string is mixed case, Then it becomes lowercase")
        func mixedCaseToLowercase() {
            let input = "Fix-Login-Bug"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-login-bug")
        }
    }

    @Suite("Given edge cases")
    struct EdgeCaseTests {

        @Test("When string is empty, Then default is returned")
        func emptyStringReturnsDefault() {
            let input = ""
            let result = input.sanitizedForBranchName()
            #expect(result == "task")
        }

        @Test("When string is just special characters, Then default is returned")
        func onlySpecialCharsReturnsDefault() {
            let input = "???***"
            let result = input.sanitizedForBranchName()
            #expect(result == "task")
        }

        @Test("When string is just @, Then default is returned")
        func atSymbolReturnsDefault() {
            let input = "@"
            let result = input.sanitizedForBranchName()
            #expect(result == "task")
        }

        @Test("When string has leading/trailing hyphens, Then they are removed")
        func leadingTrailingHyphensRemoved() {
            let input = "-fix-bug-"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-bug")
        }
    }

    @Suite("Given real-world Reminders task names")
    struct RealWorldExamplesTests {

        @Test("When task is 'Buy groceries @ Whole Foods', Then sanitized correctly")
        func groceriesTask() {
            let input = "Buy groceries @ Whole Foods"
            let result = input.sanitizedForBranchName()
            #expect(result == "buy-groceries-whole-foods")
        }

        @Test("When task is 'Fix bug #123: Login fails', Then sanitized correctly")
        func bugTask() {
            let input = "Fix bug #123: Login fails"
            let result = input.sanitizedForBranchName()
            #expect(result == "fix-bug-123-login-fails")
        }

        @Test("When task is 'Update README.md', Then sanitized correctly")
        func readmeTask() {
            let input = "Update README.md"
            let result = input.sanitizedForBranchName()
            #expect(result == "update-readme.md")
        }

        @Test("When task is 'Add feature (urgent!!!)', Then sanitized correctly")
        func urgentTask() {
            let input = "Add feature (urgent!!!)"
            let result = input.sanitizedForBranchName()
            #expect(result == "add-feature-urgent")
        }

        @Test("When task has emoji, Then emoji is handled")
        func emojiTask() {
            let input = "Fix 🐛 in login"
            let result = input.sanitizedForBranchName()
            // Emoji should be preserved or removed gracefully
            #expect(!result.isEmpty)
            #expect(result.contains("fix"))
            #expect(result.contains("login"))
        }
    }

    @Suite("Given task IDs from different trackers")
    struct TaskIDTests {

        @Test("When JIRA task ID, Then sanitized correctly")
        func jiraTaskID() {
            let input = "PROJ-123"
            let result = input.sanitizedForBranchName()
            #expect(result == "proj-123")
        }

        @Test("When Linear task ID, Then sanitized correctly")
        func linearTaskID() {
            let input = "ENG-456"
            let result = input.sanitizedForBranchName()
            #expect(result == "eng-456")
        }

        @Test("When Reminders task with special chars, Then sanitized correctly")
        func remindersTaskID() {
            let input = "Task: Fix the login bug!"
            let result = input.sanitizedForBranchName()
            #expect(result == "task-fix-the-login-bug")
        }
    }
}
