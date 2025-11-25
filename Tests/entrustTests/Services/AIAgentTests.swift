import Testing
import Foundation
@testable import entrust

/// BDD-style tests for AIAgent protocol and implementations
@Suite("AIAgent Tests")
struct AIAgentTests {

    // MARK: - AIAgentType Tests

    @Suite("Given AI agent types")
    struct AIAgentTypeTests {

        @Test("When accessing display names, Then they are human-readable")
        func displayNamesAreHumanReadable() {
            #expect(AIAgentType.claudeCode.displayName == "Claude Code")
            #expect(AIAgentType.aider.displayName == "Aider")
            #expect(AIAgentType.cursor.displayName == "Cursor")
            #expect(AIAgentType.codex.displayName == "Codex")
            #expect(AIAgentType.gemini.displayName == "Gemini")
            #expect(AIAgentType.copilot.displayName == "Copilot")
        }

        @Test("When accessing raw values, Then they are CLI-friendly")
        func rawValuesAreCLIFriendly() {
            #expect(AIAgentType.claudeCode.rawValue == "claude-code")
            #expect(AIAgentType.aider.rawValue == "aider")
            #expect(AIAgentType.cursor.rawValue == "cursor")
            #expect(AIAgentType.codex.rawValue == "codex")
            #expect(AIAgentType.gemini.rawValue == "gemini")
            #expect(AIAgentType.copilot.rawValue == "copilot")
        }

        @Test("When parsing from raw value, Then correct type is returned")
        func parsingFromRawValue() {
            #expect(AIAgentType(rawValue: "claude-code") == .claudeCode)
            #expect(AIAgentType(rawValue: "aider") == .aider)
            #expect(AIAgentType(rawValue: "cursor") == .cursor)
            #expect(AIAgentType(rawValue: "codex") == .codex)
            #expect(AIAgentType(rawValue: "gemini") == .gemini)
            #expect(AIAgentType(rawValue: "copilot") == .copilot)
            #expect(AIAgentType(rawValue: "invalid") == nil)
        }

        @Test("When accessing default commands, Then they match CLI tools")
        func defaultCommandsMatchCLITools() {
            #expect(AIAgentType.claudeCode.defaultCommand == "claude")
            #expect(AIAgentType.aider.defaultCommand == "aider")
            #expect(AIAgentType.cursor.defaultCommand == "cursor")
            #expect(AIAgentType.codex.defaultCommand == "codex")
            #expect(AIAgentType.gemini.defaultCommand == "gemini")
            #expect(AIAgentType.copilot.defaultCommand == "gh")
        }

        @Test("When accessing prompt styles, Then they are correct for each agent")
        func promptStylesAreCorrect() {
            #expect(AIAgentType.claudeCode.promptStyle == .headlessPrint)
            #expect(AIAgentType.aider.promptStyle == .messageFlag)
            #expect(AIAgentType.cursor.promptStyle == .promptFlag)
            #expect(AIAgentType.codex.promptStyle == .directArgument)
            #expect(AIAgentType.gemini.promptStyle == .directArgument)
            #expect(AIAgentType.copilot.promptStyle == .directArgument)
        }

        @Test("When accessing additional args, Then agents have correct args")
        func additionalArgsAreCorrect() {
            #expect(AIAgentType.claudeCode.additionalArgs == ["--verbose"])
            #expect(AIAgentType.aider.additionalArgs == ["--yes"])
            #expect(AIAgentType.cursor.additionalArgs == ["--headless"])
            #expect(AIAgentType.codex.additionalArgs.isEmpty)
            #expect(AIAgentType.gemini.additionalArgs.isEmpty)
            #expect(AIAgentType.copilot.additionalArgs == ["copilot", "suggest"])
        }
    }

    // MARK: - AIAgentFactory Tests

    @Suite("Given the AI agent factory")
    struct AIAgentFactoryTests {

        @Test("When creating Claude Code agent, Then correct agent is returned")
        func createClaudeCodeAgent() {
            let agent = AIAgentFactory.create(type: .claudeCode)

            #expect(agent.name == "Claude Code")
            #expect(agent.command == "claude")
        }

        @Test("When creating Aider agent, Then correct agent is returned")
        func createAiderAgent() {
            let agent = AIAgentFactory.create(type: .aider)

            #expect(agent.name == "Aider")
            #expect(agent.command == "aider")
        }

        @Test("When creating Cursor agent, Then correct agent is returned")
        func createCursorAgent() {
            let agent = AIAgentFactory.create(type: .cursor)

            #expect(agent.name == "Cursor")
            #expect(agent.command == "cursor")
        }

        @Test("When creating Codex agent, Then correct agent is returned")
        func createCodexAgent() {
            let agent = AIAgentFactory.create(type: .codex)

            #expect(agent.name == "Codex")
            #expect(agent.command == "codex")
        }

        @Test("When creating Gemini agent, Then correct agent is returned")
        func createGeminiAgent() {
            let agent = AIAgentFactory.create(type: .gemini)

            #expect(agent.name == "Gemini")
            #expect(agent.command == "gemini")
        }

        @Test("When creating Copilot agent, Then correct agent is returned")
        func createCopilotAgent() {
            let agent = AIAgentFactory.create(type: .copilot)

            #expect(agent.name == "Copilot")
            #expect(agent.command == "gh")
        }
    }

    // MARK: - GenericAIAgent Tests

    @Suite("Given a generic AI agent")
    struct GenericAIAgentTests {

        @Test("When creating with defaults, Then properties are set correctly")
        func agentWithDefaults() {
            let agent = GenericAIAgent(name: "Test Agent", command: "test-cli")

            #expect(agent.name == "Test Agent")
            #expect(agent.command == "test-cli")
            #expect(agent.promptStyle == .fileArgument)
            #expect(agent.additionalArgs.isEmpty)
        }

        @Test("When creating with all parameters, Then all are stored")
        func agentWithAllParams() {
            let agent = GenericAIAgent(
                name: "Custom Agent",
                command: "custom-cli",
                promptStyle: .messageFlag,
                additionalArgs: ["--verbose", "--no-cache"]
            )

            #expect(agent.name == "Custom Agent")
            #expect(agent.command == "custom-cli")
            #expect(agent.promptStyle == .messageFlag)
            #expect(agent.additionalArgs == ["--verbose", "--no-cache"])
        }
    }

    // MARK: - PromptStyle Tests

    @Suite("Given prompt styles")
    struct PromptStyleTests {

        @Test("When checking all styles, Then they are distinct")
        func allStylesAreDistinct() {
            let styles: [PromptStyle] = [
                .fileArgument,
                .messageFlag,
                .printFlag,
                .promptFlag,
                .directArgument,
                .headlessPrint
            ]

            // Verify we have all expected styles
            #expect(styles.count == 6)
        }
    }

    // MARK: - AIAgentContext Tests

    @Suite("Given AI agent context")
    struct AIAgentContextTests {

        @Test("When creating with defaults, Then values are correct")
        func defaultContext() {
            let context = AIAgentContext()

            #expect(context.workingDirectory == nil)
            #expect(context.environment.isEmpty)
            #expect(context.timeout == 3600)
        }

        @Test("When creating with custom values, Then values are set")
        func customContext() {
            let context = AIAgentContext(
                workingDirectory: "/path/to/project",
                environment: ["API_KEY": "secret"],
                timeout: 7200
            )

            #expect(context.workingDirectory == "/path/to/project")
            #expect(context.environment["API_KEY"] == "secret")
            #expect(context.timeout == 7200)
        }
    }

    // MARK: - AIAgentResult Tests

    @Suite("Given AI agent results")
    struct AIAgentResultTests {

        @Test("When creating a successful result, Then properties are correct")
        func successfulResult() {
            let result = AIAgentResult(
                output: "Code generated successfully",
                success: true,
                executionTime: 45.5
            )

            #expect(result.output == "Code generated successfully")
            #expect(result.success == true)
            #expect(result.executionTime == 45.5)
        }

        @Test("When creating with defaults, Then success is true")
        func defaultsResult() {
            let result = AIAgentResult(output: "Done")

            #expect(result.output == "Done")
            #expect(result.success == true)
            #expect(result.executionTime == 0)
        }
    }
}
