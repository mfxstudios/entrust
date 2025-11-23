import Foundation

enum AutomationError: LocalizedError {
    case configurationNotFound
    case invalidTrackerType
    case missingJIRAConfiguration
    case issueFetchFailed
    case issueUpdateFailed
    case issueNotFound
    case prCreationFailed
    case testsFailed
    case shellCommandFailed(String)
    case keychainSaveFailed(String)
    case keychainLoadFailed(String)
    case keychainDeleteFailed(String)
    case missingGitHubToken
    case statusFetchFailed
    case statusChangeFailed
    case invalidStatus(String, available: [String])
    case noTicketsProvided

    // Reminders-specific errors
    case remindersAccessDenied
    case remindersListNotFound(String)
    case missingRemindersConfiguration

    var errorDescription: String? {
        switch self {
        case .configurationNotFound:
            return "Configuration not found. Run 'entrust setup' first."
        case .invalidTrackerType:
            return "Invalid tracker type. Must be 'jira' or 'linear'."
        case .missingJIRAConfiguration:
            return "Missing JIRA configuration (URL or email)"
        case .issueFetchFailed:
            return "Failed to fetch issue"
        case .issueUpdateFailed:
            return "Failed to update issue"
        case .issueNotFound:
            return "Issue not found"
        case .prCreationFailed:
            return "Failed to create pull request"
        case .testsFailed:
            return "Tests failed"
        case .shellCommandFailed(let output):
            return "Shell command failed: \(output)"
        case .keychainSaveFailed(let key):
            return "Failed to save \(key) to keychain"
        case .keychainLoadFailed(let key):
            return "Failed to load \(key) from keychain. Run 'entrust setup' first."
        case .keychainDeleteFailed(let key):
            return "Failed to delete \(key) from keychain"
        case .missingGitHubToken:
            return "GitHub token required when not using GitHub CLI"
        case .statusFetchFailed:
            return "Failed to fetch available statuses"
        case .statusChangeFailed:
            return "Failed to change status"
        case .invalidStatus(let status, let available):
            return "Invalid status '\(status)'. Available: \(available.joined(separator: ", "))"
        case .noTicketsProvided:
            return "No tickets provided. Use arguments or --file option."
        case .remindersAccessDenied:
            return "Access to Reminders denied. Please grant access in System Settings > Privacy & Security > Reminders."
        case .remindersListNotFound(let name):
            return "Reminders list '\(name)' not found. Please create it in the Reminders app first."
        case .missingRemindersConfiguration:
            return "Missing Reminders configuration (list name)"
        }
    }
}
