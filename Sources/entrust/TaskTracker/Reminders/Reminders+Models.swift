//
//  Reminders+Models.swift
//  entrust
//
//  Created by Prince Ugwuh on 11/22/25.
//

import Foundation

/// Represents a Reminders list configuration
struct RemindersListConfig: Codable {
    let listName: String

    /// Status mapping from generic status names to Reminders list names
    /// e.g., "In Progress" -> "Working On", "In Review" -> "Review"
    let statusMapping: [String: String]?
}

/// Default status mappings for common workflow states
enum RemindersDefaultStatus {
    static let backlog = "Backlog"
    static let inProgress = "In Progress"
    static let inReview = "In Review"
    static let done = "Done"

    /// Default mapping assumes lists are named after workflow states
    static let defaultMapping: [String: String] = [
        "Backlog": "Backlog",
        "In Progress": "In Progress",
        "In Review": "In Review",
        "Done": "Done"
    ]
}
