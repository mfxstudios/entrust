import ArgumentParser
import Foundation

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Change issue status"
    )
    
    @Argument(help: "Ticket ID (e.g., IOS-1234 or PRO-123)")
    var ticketID: String
    
    @Argument(help: "New status (e.g., 'In Progress', 'In Review', 'Done')")
    var status: String
    
    @Flag(name: .long, help: "List available statuses for this issue")
    var list: Bool = false
    
    @Option(name: .long, help: "Override task tracker type [jira/linear]")
    var tracker: String?
    
    func run() async throws {
        let config = try ConfigurationManager.load()
        let effectiveTracker = tracker ?? config.trackerType
        
        // Load credentials and create tracker
        let taskTracker: TaskTracker
        
        if effectiveTracker == "jira" {
            guard let jiraURL = config.jiraURL, let jiraEmail = config.jiraEmail else {
                throw AutomationError.missingJIRAConfiguration
            }
            let jiraToken = try KeychainManager.load(.jiraToken)
            taskTracker = JIRATracker(url: jiraURL, email: jiraEmail, token: jiraToken)
        } else {
            let linearToken = try KeychainManager.load(.linearToken)
            taskTracker = LinearTracker(token: linearToken)
        }
        
        if list {
            print("📋 Available statuses for \(ticketID):")
            let statuses = try await taskTracker.getAvailableStatuses(ticketID)
            for status in statuses {
                print("  • \(status.name)")
                if let description = status.description {
                    print("    \(description)")
                }
            }
            return
        }
        
        print("🔄 Changing status for \(ticketID) to '\(status)'...")
        try await taskTracker.changeStatus(ticketID, to: status)
        print("✅ Status changed successfully!")
    }
}
