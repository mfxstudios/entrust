import ArgumentParser
import Foundation
import ClaudeCodeSDK

struct Continue: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Continue a previous Claude Code session with additional instructions"
    )

    @Argument(help: "Session ID to continue (or 'latest' for most recent)")
    var sessionID: String

    @Argument(help: "Additional prompt/instructions to continue with")
    var prompt: String

    @Option(name: .long, help: "Working directory for the session")
    var workingDirectory: String?

    func run() async throws {
        _ = try ConfigurationManager.load()

        // Get working directory
        let effectiveWorkingDirectory: String
        if let workingDirectory = workingDirectory {
            effectiveWorkingDirectory = workingDirectory
        } else {
            effectiveWorkingDirectory = try await Shell.run("git", "rev-parse", "--show-toplevel")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        print("🔄 Continuing Claude Code session...")
        print("📂 Working directory: \(effectiveWorkingDirectory)")
        print("💬 Prompt: \(prompt)\n")

        // Configure ClaudeCodeSDK
        var claudeConfig = ClaudeCodeConfiguration.default
        claudeConfig.workingDirectory = effectiveWorkingDirectory
        claudeConfig.backend = NodePathDetector.isAgentSDKInstalled() ? .agentSDK : .headless

        if let nvmPath = NvmPathDetector.detectNvmPath() {
            claudeConfig.additionalPaths.append(nvmPath)
        }

        let client = try ClaudeCodeClient(configuration: claudeConfig)

        // Resolve session ID
        let actualSessionID: String
        if sessionID.lowercased() == "latest" {
            print("🔍 Finding latest session...")
            let storage = ClaudeNativeSessionStorage()
            if let recentSession = try await storage.getMostRecentSession(for: effectiveWorkingDirectory) {
                actualSessionID = recentSession.id
                print("✅ Found latest session: \(actualSessionID.prefix(8))...")
            } else {
                print("❌ No sessions found for this directory")
                throw AutomationError.configurationNotFound
            }
        } else {
            actualSessionID = sessionID
        }

        // Configure options
        var options = ClaudeCodeOptions()
        options.verbose = true

        // Continue conversation
        let result = try await client.resumeConversation(
            sessionId: actualSessionID,
            prompt: prompt,
            outputFormat: .text,
            options: options
        )

        // Print result
        switch result {
        case .text(let content):
            print("\n📄 Response:\n")
            print(content)
        case .json(let response):
            print("\n📄 Session ID: \(response.sessionId)")
        case .stream:
            print("\n📄 Streaming response received")
        }

        print("\n✅ Conversation continued successfully")
    }
}
