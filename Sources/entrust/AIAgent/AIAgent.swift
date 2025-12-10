import Foundation
import ClaudeCodeSDK
@preconcurrency import Combine

/// Result of an AI agent execution
struct AIAgentResult: Sendable {
    let output: String
    let success: Bool
    let executionTime: TimeInterval
    let sessionId: String?

    init(output: String, success: Bool = true, executionTime: TimeInterval = 0, sessionId: String? = nil) {
        self.output = output
        self.success = success
        self.executionTime = executionTime
        self.sessionId = sessionId
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

    /// Continue a previous conversation with a session ID
    func continueConversation(sessionId: String, prompt: String, context: AIAgentContext) async throws -> AIAgentResult

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

/// Claude Code AI agent - using ClaudeCodeSDK
struct ClaudeCodeAgent: AIAgent, Sendable {
    let name: String = "Claude Code"
    let command: String = "claude"

    func execute(prompt: String, context: AIAgentContext) async throws -> AIAgentResult {
        try await executeInternal(prompt: prompt, context: context, sessionId: nil)
    }

    func continueConversation(sessionId: String, prompt: String, context: AIAgentContext) async throws -> AIAgentResult {
        try await executeInternal(prompt: prompt, context: context, sessionId: sessionId)
    }

    private func executeInternal(prompt: String, context: AIAgentContext, sessionId: String?) async throws -> AIAgentResult {
        let startTime = Date()

        // Configure ClaudeCodeSDK
        var config = ClaudeCodeConfiguration.default
        config.enableDebugLogging = false
        config.workingDirectory = context.workingDirectory

        if !context.environment.isEmpty {
            config.environment = context.environment
        }

        // Auto-detect best backend (Agent SDK is 2-10x faster)
        let detector = BackendDetector(configuration: config)
        config.backend = detector.detect().recommendedBackend

        let client = try ClaudeCodeClient(configuration: config)

        // Configure options
        var options = ClaudeCodeOptions()
        options.verbose = true
        options.timeout = context.timeout
        options.permissionMode = .bypassPermissions
        options.appendSystemPrompt = """
        When you're done implementing the changes:
        1. Verify all files compile without errors
        2. Ensure all changes are saved
        3. Confirm the implementation is complete
        """

        // Execute with streaming for real-time output
        if let sessionId = sessionId {
            print("🤖 Claude Code continuing conversation (session: \(sessionId.prefix(8))...) with \(config.backend == .agentSDK ? "Agent SDK" : "Headless") backend...")
        } else {
            print("🤖 Claude Code starting execution with \(config.backend == .agentSDK ? "Agent SDK" : "Headless") backend...")
        }
        print("")  // Add newline before output

        do {
            let stream: ClaudeCodeStream

            if let sessionId = sessionId {
                // Continue existing conversation with streaming
                let result = try await client.resumeConversation(
                    sessionId: sessionId,
                    prompt: prompt,
                    outputFormat: .streamJson,
                    options: options
                )
                guard case .stream(let resultStream) = result else {
                    throw ClaudeCodeError.invalidOutput("Expected stream result")
                }
                stream = resultStream
            } else {
                // Start new conversation with streaming
                stream = try await client.runStream(prompt, options: options)
            }

            // Process stream and collect output in real-time
            var collectedText: [String] = []
            var finalSessionId: String?

            for try await chunk in stream {
                // Extract session ID
                finalSessionId = chunk.sessionId

                // Handle different chunk types
                switch chunk {
                case .assistant(let assistantMsg):
                    // Print assistant messages in real-time
                    for contentBlock in assistantMsg.message.content {
                        switch contentBlock {
                        case .text(let textContent):
                            print(textContent.text, terminator: "")
                            fflush(stdout)
                            collectedText.append(textContent.text)
                        case .toolUse(let toolUse):
                            print("\n🔧 Using tool: \(toolUse.name)")
                        default:
                            break
                        }
                    }

                case .result(let resultMsg):
                    // Final result message
                    finalSessionId = resultMsg.sessionId

                default:
                    // Ignore other chunk types (initSystem, user)
                    break
                }
            }

            let executionTime = Date().timeIntervalSince(startTime)

            print("\n✅ Claude Code finished")
            print("📊 Execution completed in \(Int(executionTime))s")

            let output = collectedText.joined()

            return AIAgentResult(
                output: output,
                success: true,
                executionTime: executionTime,
                sessionId: finalSessionId
            )

        } catch let error as ClaudeCodeError {
            print("\n❌ Claude Code error: \(error.localizedDescription)")

            if error.isRetryable, let delay = error.suggestedRetryDelay {
                print("⚠️  Error is retryable, suggested delay: \(delay)s")
            }

            throw error
        }
    }
}

/// Factory for creating AI agents (only Claude Code supported)
enum AIAgentFactory {
    static func create(type: AIAgentType) -> any AIAgent {
        return ClaudeCodeAgent()
    }
}
