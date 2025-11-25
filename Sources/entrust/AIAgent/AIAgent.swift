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

/// How the prompt is passed to the AI CLI tool
enum PromptStyle: Sendable {
    /// Pass prompt file path as argument: `tool <file>`
    case fileArgument
    /// Pass prompt via --message flag: `tool --message <prompt>`
    case messageFlag
    /// Pass prompt file via --print flag: `tool --print <file>`
    case printFlag
    /// Pass prompt file via --prompt flag: `tool --prompt <file>`
    case promptFlag
    /// Pass prompt directly as argument: `tool <prompt>`
    case directArgument
    /// Pass prompt via -p flag for headless mode: `tool -p <prompt>`
    case headlessPrint
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

/// Supported AI agent types
enum AIAgentType: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case aider = "aider"
    case cursor = "cursor"
    case codex = "codex"
    case gemini = "gemini"
    case copilot = "copilot"

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .aider: return "Aider"
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .copilot: return "Copilot"
        }
    }

    var defaultCommand: String {
        switch self {
        case .claudeCode: return "claude"
        case .aider: return "aider"
        case .cursor: return "cursor"
        case .codex: return "codex"
        case .gemini: return "gemini"
        case .copilot: return "gh"
        }
    }

    var promptStyle: PromptStyle {
        switch self {
        case .claudeCode: return .headlessPrint
        case .aider: return .messageFlag
        case .cursor: return .promptFlag
        case .codex: return .directArgument
        case .gemini: return .directArgument
        case .copilot: return .directArgument
        }
    }

    var additionalArgs: [String] {
        switch self {
        case .claudeCode: return ["--verbose"]  // Enable verbose logging for debugging
        case .aider: return ["--yes"]  // Auto-confirm all prompts for headless mode
        case .cursor: return ["--headless"]  // Enable headless/non-interactive mode
        case .copilot: return ["copilot", "suggest"]
        default: return []
        }
    }
}

/// Generic AI agent that works with any CLI tool
struct GenericAIAgent: AIAgent, Sendable {
    let name: String
    let command: String
    let promptStyle: PromptStyle
    let additionalArgs: [String]

    init(
        name: String,
        command: String,
        promptStyle: PromptStyle = .fileArgument,
        additionalArgs: [String] = []
    ) {
        self.name = name
        self.command = command
        self.promptStyle = promptStyle
        self.additionalArgs = additionalArgs
    }

    func execute(prompt: String, context: AIAgentContext) async throws -> AIAgentResult {
        let startTime = Date()

        let output: String

        switch promptStyle {
        case .messageFlag:
            // Pass prompt directly via --message flag (e.g., aider)
            output = try await executeWithArgs(
                additionalArgs + ["--message", prompt],
                context: context
            )

        case .headlessPrint:
            // Pass prompt directly via -p flag for headless mode (e.g., claude)
            output = try await executeWithArgs(
                additionalArgs + ["-p", prompt],
                context: context
            )

        case .printFlag, .promptFlag, .fileArgument:
            // Write prompt to temporary file
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("ai-prompt-\(UUID().uuidString).txt")

            try prompt.write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let args: [String]
            switch promptStyle {
            case .printFlag:
                args = additionalArgs + ["--print", tempFile.path]
            case .promptFlag:
                args = additionalArgs + ["--prompt", tempFile.path]
            case .fileArgument:
                args = additionalArgs + [tempFile.path]
            default:
                args = additionalArgs + [tempFile.path]
            }

            output = try await executeWithArgs(args, context: context)

        case .directArgument:
            // Pass prompt directly as argument
            output = try await executeWithArgs(
                additionalArgs + [prompt],
                context: context
            )
        }

        let executionTime = Date().timeIntervalSince(startTime)

        return AIAgentResult(
            output: output,
            success: true,
            executionTime: executionTime
        )
    }

    private func executeWithArgs(_ args: [String], context: AIAgentContext) async throws -> String {
        if let workingDir = context.workingDirectory {
            return try await Shell.runInDirectory(workingDir, args: [command] + args, streamOutput: true)
        } else {
            return try await Shell.run([command] + args, streamOutput: true)
        }
    }
}

/// Factory for creating AI agents
enum AIAgentFactory {
    static func create(type: AIAgentType) -> any AIAgent {
        return GenericAIAgent(
            name: type.displayName,
            command: type.defaultCommand,
            promptStyle: type.promptStyle,
            additionalArgs: type.additionalArgs
        )
    }
}
