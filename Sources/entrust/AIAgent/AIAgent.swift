import Foundation

/// Result of an AI agent execution
struct AIAgentResult: Sendable {
    let output: String
    let success: Bool
    let executionTime: TimeInterval

    init(output: String, success: Bool = true, executionTime: TimeInterval = 0) {
        self.output = output
        self.success = success
        self.executionTime = executionTime
    }
}

/// Context provided to the AI agent for task execution
struct AIAgentContext: Sendable {
    let workingDirectory: String?
    let environment: [String: String]
    let timeout: TimeInterval

    init(
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval = 3600 // 1 hour default
    ) {
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
    }
}


/// Protocol for AI coding agents - enables support for different AI CLI tools
protocol AIAgent: Sendable {
    /// The name of the AI agent (e.g., "Claude Code", "Cursor", "Aider")
    var name: String { get }

    /// The CLI command used to invoke the agent
    var command: String { get }

    /// Execute the agent with a given prompt
    func execute(prompt: String, context: AIAgentContext) async throws -> AIAgentResult

    /// Check if the agent is available/installed
    func isAvailable() async -> Bool
}

// MARK: - Default Implementation

extension AIAgent {
    func isAvailable() async -> Bool {
        do {
            _ = try await Shell.run("which", command)
            return true
        } catch {
            return false
        }
    }
}

/// Claude Code - the only supported AI agent
enum AIAgentType: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"

    var displayName: String {
        return "Claude Code"
    }

    var defaultCommand: String {
        return "claude"
    }

    var additionalArgs: [String] {
        return ["-p"]  // Headless print mode
    }
}

/// Claude Code AI agent - simplified to just run claude -p
struct ClaudeCodeAgent: AIAgent, Sendable {
    let name: String = "Claude Code"
    let command: String = "claude"

    func execute(prompt: String, context: AIAgentContext) async throws -> AIAgentResult {
        let startTime = Date()

        // Run: claude -p --dangerously-skip-permissions "prompt"
        let args = [command, "-p", "--dangerously-skip-permissions", prompt]

        let output = try await Shell.run(
            args,
            streamOutput: true,
            workingDirectory: context.workingDirectory
        )

        let executionTime = Date().timeIntervalSince(startTime)

        return AIAgentResult(
            output: output,
            success: true,
            executionTime: executionTime
        )
    }
}

/// Factory for creating AI agents (only Claude Code supported)
enum AIAgentFactory {
    static func create(type: AIAgentType) -> any AIAgent {
        return ClaudeCodeAgent()
    }
}
