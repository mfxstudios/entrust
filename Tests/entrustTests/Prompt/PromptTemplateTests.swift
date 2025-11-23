//
//  PromptTemplateTests.swift
//  entrustTests
//
//  Created by Prince Ugwuh on 11/22/25.
//

import Testing
import Foundation
@testable import entrust

/// BDD-style tests for PromptTemplate system
@Suite("PromptTemplate Tests")
struct PromptTemplateTests {

    // MARK: - PromptVariables Tests

    @Suite("Given prompt variables")
    struct PromptVariablesTests {

        @Test("When creating with all fields, Then all are accessible")
        func createWithAllFields() {
            let variables = PromptVariables(
                taskTitle: "Implement login",
                taskDescription: "Add OAuth support",
                taskID: "TASK-123",
                additionalContext: "Use Firebase"
            )

            #expect(variables.taskTitle == "Implement login")
            #expect(variables.taskDescription == "Add OAuth support")
            #expect(variables.taskID == "TASK-123")
            #expect(variables.additionalContext == "Use Firebase")
        }

        @Test("When creating from TaskIssue, Then fields are mapped correctly")
        func createFromTaskIssue() {
            let issue = TaskIssue(
                id: "ENG-456",
                title: "Fix bug in parser",
                description: "Parser fails on empty input"
            )
            let variables = PromptVariables(from: issue)

            #expect(variables.taskTitle == "Fix bug in parser")
            #expect(variables.taskDescription == "Parser fails on empty input")
            #expect(variables.taskID == "ENG-456")
            #expect(variables.additionalContext == nil)
        }

        @Test("When creating from TaskIssue with nil description, Then default is used")
        func createFromTaskIssueWithNilDescription() {
            let issue = TaskIssue(
                id: "ENG-789",
                title: "Quick fix",
                description: nil
            )
            let variables = PromptVariables(from: issue)

            #expect(variables.taskDescription == "No description provided")
        }

        @Test("When creating from TaskIssue with additional context, Then context is included")
        func createFromTaskIssueWithContext() {
            let issue = TaskIssue(
                id: "ENG-101",
                title: "Add feature",
                description: "Feature description"
            )
            let variables = PromptVariables(from: issue, additionalContext: "Extra info")

            #expect(variables.additionalContext == "Extra info")
        }
    }

    // MARK: - DefaultPromptTemplate Tests

    @Suite("Given the default prompt template")
    struct DefaultPromptTemplateTests {

        @Test("When rendering, Then task title is included")
        func renderIncludesTitle() {
            let template = DefaultPromptTemplate()
            let variables = PromptVariables(
                taskTitle: "My Task Title",
                taskDescription: "Description",
                taskID: "TASK-1"
            )

            let result = template.render(with: variables)

            #expect(result.contains("Task: My Task Title"))
        }

        @Test("When rendering, Then description is included")
        func renderIncludesDescription() {
            let template = DefaultPromptTemplate()
            let variables = PromptVariables(
                taskTitle: "Title",
                taskDescription: "My detailed description",
                taskID: "TASK-1"
            )

            let result = template.render(with: variables)

            #expect(result.contains("Description: My detailed description"))
        }

        @Test("When rendering, Then requirements are included")
        func renderIncludesRequirements() {
            let template = DefaultPromptTemplate()
            let variables = PromptVariables(
                taskTitle: "Title",
                taskDescription: "Description",
                taskID: "TASK-1"
            )

            let result = template.render(with: variables)

            #expect(result.contains("Requirements:"))
            #expect(result.contains("Swift 6"))
            #expect(result.contains("swift test"))
        }

        @Test("When rendering with additional context, Then context is appended")
        func renderIncludesAdditionalContext() {
            let template = DefaultPromptTemplate()
            let variables = PromptVariables(
                taskTitle: "Title",
                taskDescription: "Description",
                taskID: "TASK-1",
                additionalContext: "Use the new API"
            )

            let result = template.render(with: variables)

            #expect(result.contains("Additional Context:"))
            #expect(result.contains("Use the new API"))
        }

        @Test("When rendering without context, Then no context section")
        func renderWithoutContext() {
            let template = DefaultPromptTemplate()
            let variables = PromptVariables(
                taskTitle: "Title",
                taskDescription: "Description",
                taskID: "TASK-1",
                additionalContext: nil
            )

            let result = template.render(with: variables)

            #expect(!result.contains("Additional Context:"))
        }
    }
}
