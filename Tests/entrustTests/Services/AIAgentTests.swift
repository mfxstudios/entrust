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
        func displayNamesAreCorrect() {
            #expect(AIAgentType.claudeCode.displayName == "Claude Code")
        }

        @Test("When accessing default commands, Then they match CLI tools")
        func defaultCommandsAreCorrect() {
            #expect(AIAgentType.claudeCode.defaultCommand == "claude")
        }

        @Test("When accessing additional args, Then Claude Code has -p flag")
        func additionalArgsAreCorrect() {
            #expect(AIAgentType.claudeCode.additionalArgs == ["-p"])
        }

        @Test("When accessing raw values, Then they are CLI-friendly")
        func rawValuesAreCorrect() {
            #expect(AIAgentType.claudeCode.rawValue == "claude-code")
        }

        @Test("When parsing from raw value, Then correct type is returned")
        func parsingFromRawValue() {
            #expect(AIAgentType(rawValue: "claude-code") == .claudeCode)
            #expect(AIAgentType(rawValue: "invalid") == nil)
        }
    }

    // MARK: - AIAgentFactory Tests

    @Suite("Given the AI agent factory")
    struct AIAgentFactoryTests {

        @Test("When creating Claude Code agent, Then correct agent is returned")
        func createClaudeCodeAgent() {
            let agent = AIAgentFactory.create(type: .claudeCode)
            #expect(agent.name == "Claude Code")
        }
    }

    // MARK: - AIAgentContext Tests

    @Suite("Given AI agent context")
    struct AIAgentContextTests {

        @Test("When creating with defaults, Then properties are set correctly")
        func defaultsAreCorrect() {
            let context = AIAgentContext()
            #expect(context.workingDirectory == nil)
            #expect(context.environment.isEmpty)
            #expect(context.timeout == 3600)
        }

        @Test("When creating with custom values, Then values are set")
        func customValuesAreSet() {
            let context = AIAgentContext(
                workingDirectory: "/tmp/test",
                environment: ["KEY": "VALUE"],
                timeout: 1800
            )
            #expect(context.workingDirectory == "/tmp/test")
            #expect(context.environment["KEY"] == "VALUE")
            #expect(context.timeout == 1800)
        }
    }

    // MARK: - AIAgentResult Tests

    @Suite("Given AI agent results")
    struct AIAgentResultTests {

        @Test("When creating with defaults, Then success is true")
        func defaultsToSuccess() {
            let result = AIAgentResult(output: "test")
            #expect(result.output == "test")
            #expect(result.success == true)
            #expect(result.executionTime == 0)
        }

        @Test("When creating with all fields, Then all are accessible")
        func allFieldsAccessible() {
            let result = AIAgentResult(
                output: "test output",
                success: false,
                executionTime: 123.45
            )
            #expect(result.output == "test output")
            #expect(result.success == false)
            #expect(result.executionTime == 123.45)
        }
    }
}
