//
//  PromptTemplate.swift
//  entrust
//
//  Created by Prince Ugwuh on 11/22/25.
//

import Foundation

/// Variables that can be substituted in prompt templates
struct PromptVariables: Sendable {
    let taskTitle: String
    let taskDescription: String
    let taskID: String
    let additionalContext: String?

    init(
        taskTitle: String,
        taskDescription: String,
        taskID: String,
        additionalContext: String? = nil
    ) {
        self.taskTitle = taskTitle
        self.taskDescription = taskDescription
        self.taskID = taskID
        self.additionalContext = additionalContext
    }

    init(from issue: TaskIssue, additionalContext: String? = nil) {
        self.taskTitle = issue.title
        self.taskDescription = issue.description ?? "No description provided"
        self.taskID = issue.id
        self.additionalContext = additionalContext
    }
}

/// Protocol for prompt templates
protocol PromptTemplate: Sendable {
    /// Render the template with the given variables
    func render(with variables: PromptVariables) -> String
}

/// Default prompt template with sensible defaults
struct DefaultPromptTemplate: PromptTemplate, Sendable {
    func render(with variables: PromptVariables) -> String {
        var prompt = """
        Task: \(variables.taskTitle)
        Description: \(variables.taskDescription)

        Requirements:
        1. Analyze the existing codebase to understand relevant files
        2. Create an implementation plan
        3. Implement changes following:
           - Swift 6 with strict concurrency
           - SwiftUI for views
           - Observation framework for state management
           - Swift concurrency (async/await, AsyncSequence)
        4. Write tests using Swift Testing framework (#expect, #require)
        5. Verify tests pass with `swift test`
        6. Ensure code compiles without warnings

        Please implement this feature completely and run all tests.
        """

        if let context = variables.additionalContext {
            prompt += "\n\nAdditional Context:\n\(context)"
        }

        return prompt
    }
}
