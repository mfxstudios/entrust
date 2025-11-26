import ArgumentParser
import Foundation
import ClaudeCodeSDK

struct Sessions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "View Claude Code session history"
    )

    @Option(name: .long, help: "Filter sessions by project path")
    var project: String?

    @Flag(name: .long, help: "Show detailed session information")
    var verbose: Bool = false

    @Option(name: .long, help: "Limit number of sessions to show")
    var limit: Int?

    func run() async throws {
        let storage = ClaudeNativeSessionStorage()

        print("📚 Claude Code Session History\n")

        if let project = project {
            print("📂 Project: \(project)\n")
            let sessions = try await storage.getSessions(for: project)

            if sessions.isEmpty {
                print("No sessions found for this project")
                return
            }

            printSessions(sessions)
        } else {
            // Show all projects with sessions
            let projects = try await storage.listProjects()

            if projects.isEmpty {
                print("No sessions found")
                return
            }

            print("Found \(projects.count) project(s) with sessions:\n")

            for project in projects {
                print("📂 \(project)")

                let sessions = try await storage.getSessions(for: project)
                let limitedSessions = limit.map { Array(sessions.prefix($0)) } ?? sessions

                printSessions(limitedSessions, indent: "   ")
                print("")
            }
        }
    }

    private func printSessions(_ sessions: [ClaudeStoredSession], indent: String = "") {
        let sortedSessions = sessions.sorted { $0.createdAt > $1.createdAt }
        let displaySessions = limit.map { Array(sortedSessions.prefix($0)) } ?? sortedSessions

        for (index, session) in displaySessions.enumerated() {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let dateStr = formatter.string(from: session.createdAt)

            print("\(indent)\(index + 1). Session \(session.id.prefix(8))... (\(dateStr))")

            if verbose {
                print("\(indent)   Messages: \(session.messages.count)")
                print("\(indent)   Project: \(session.projectPath)")
                print("\(indent)   Created: \(session.createdAt)")
            }
        }

        if let limit = limit, sessions.count > limit {
            print("\(indent)... and \(sessions.count - limit) more")
        }
    }
}
