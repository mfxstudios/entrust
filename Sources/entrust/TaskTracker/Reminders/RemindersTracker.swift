//
//  RemindersTracker.swift
//  entrust
//
//  Created by Prince Ugwuh on 11/22/25.
//

import EventKit
import Foundation

/// Internal struct to transfer reminder data across concurrency boundaries
private struct ReminderData: Sendable {
    let calendarIdentifier: String
    let title: String?
    let notes: String?
}

struct RemindersTracker: TaskTracker, @unchecked Sendable {
    let eventStore: EKEventStore
    let listName: String

    var baseURL: String { "reminders:///" }

    // Marker to track section in notes
    private let sectionMarker = "[Section:"

    init(listName: String) {
        self.eventStore = EKEventStore()
        self.listName = listName
    }

    /// Request access to Reminders. Must be called before any other operations.
    func requestAccess() async throws {
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else {
            throw AutomationError.remindersAccessDenied
        }
    }

    /// Find the reminder list (calendar) by name
    private func findList() throws -> EKCalendar {
        let calendars = eventStore.calendars(for: .reminder)
        guard let calendar = calendars.first(where: { $0.title == listName }) else {
            throw AutomationError.remindersListNotFound(listName)
        }
        return calendar
    }

    /// Extract section from notes
    private func extractSection(from notes: String?) -> String? {
        guard let notes = notes else { return nil }
        guard let range = notes.range(of: "\(sectionMarker) ") else { return nil }

        let startIndex = range.upperBound
        guard let endRange = notes[startIndex...].range(of: "]") else { return nil }

        return String(notes[startIndex..<endRange.lowerBound])
    }

    /// Update notes with new section
    private func updateNotesWithSection(_ notes: String?, section: String) -> String {
        // Remove existing section marker if present
        var cleanNotes = notes ?? ""
        if let range = cleanNotes.range(of: "\(sectionMarker) .*?\\]", options: .regularExpression) {
            cleanNotes.removeSubrange(range)
            cleanNotes = cleanNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Add new section at the beginning
        let sectionLine = "\(sectionMarker) \(section)]"
        return cleanNotes.isEmpty ? sectionLine : "\(sectionLine)\n\(cleanNotes)"
    }

    /// Get notes without section marker for display
    private func cleanNotes(_ notes: String?) -> String? {
        guard let notes = notes else { return nil }
        var cleaned = notes
        if let range = cleaned.range(of: "\(sectionMarker) .*?\\]", options: .regularExpression) {
            cleaned.removeSubrange(range)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Fetch reminders and extract Sendable data
    private func fetchReminderData(matching predicate: NSPredicate) async throws -> [ReminderData] {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                if let reminders = reminders {
                    let data = reminders.map { reminder in
                        ReminderData(
                            calendarIdentifier: reminder.calendar?.calendarIdentifier ?? "",
                            title: reminder.title,
                            notes: reminder.notes
                        )
                    }
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: AutomationError.issueFetchFailed)
                }
            }
        }
    }

    /// Find a reminder by its title (used as ID)
    private func findReminder(byTitle title: String) throws -> EKReminder {
        let calendar = try findList()
        let predicate = eventStore.predicateForReminders(in: [calendar])

        // Use synchronous fetch for operations that need the actual EKReminder object
        var foundReminder: EKReminder?
        let semaphore = DispatchSemaphore(value: 0)

        eventStore.fetchReminders(matching: predicate) { reminders in
            foundReminder = reminders?.first { $0.title == title }
            semaphore.signal()
        }

        semaphore.wait()

        guard let reminder = foundReminder else {
            throw AutomationError.issueNotFound
        }

        return reminder
    }

    func fetchIssue(_ id: String) async throws -> TaskIssue {
        try await requestAccess()

        let calendar = try findList()
        let predicate = eventStore.predicateForReminders(in: [calendar])
        let reminderDataList = try await fetchReminderData(matching: predicate)

        guard let data = reminderDataList.first(where: { $0.title == id }) else {
            throw AutomationError.issueNotFound
        }

        return TaskIssue(
            id: data.title ?? id,
            title: data.title ?? "Untitled",
            description: cleanNotes(data.notes)
        )
    }

    func updateIssue(_ id: String, prURL: String) async throws {
        try await requestAccess()

        let reminder = try findReminder(byTitle: id)

        // Get clean notes (without section marker) and append PR URL
        let cleanedNotes = cleanNotes(reminder.notes) ?? ""
        let separator = cleanedNotes.isEmpty ? "" : "\n\n"
        let newNotes = "\(cleanedNotes)\(separator)🤖 Automated PR: \(prURL)"

        // Preserve section if it exists
        if let section = extractSection(from: reminder.notes) {
            reminder.notes = updateNotesWithSection(newNotes, section: section)
        } else {
            reminder.notes = newNotes
        }

        try eventStore.save(reminder, commit: true)
    }

    func getAvailableStatuses(_ id: String) async throws -> [IssueStatus] {
        // Extract sections from all reminders in the configured list
        try await requestAccess()

        let calendar = try findList()
        let predicate = eventStore.predicateForReminders(in: [calendar])
        let reminderDataList = try await fetchReminderData(matching: predicate)

        // Extract unique section names from notes
        let sections = Set(reminderDataList.compactMap { extractSection(from: $0.notes) })
            .sorted()

        // If no sections found, return common defaults
        if sections.isEmpty {
            return [
                IssueStatus(id: "backlog", name: "Backlog", description: nil),
                IssueStatus(id: "in-progress", name: "In Progress", description: nil),
                IssueStatus(id: "in-review", name: "In Review", description: nil),
                IssueStatus(id: "done", name: "Done", description: nil)
            ]
        }

        return sections.map { section in
            IssueStatus(
                id: section.lowercased().replacingOccurrences(of: " ", with: "-"),
                name: section,
                description: nil
            )
        }
    }

    func changeStatus(_ id: String, to status: String) async throws {
        try await requestAccess()

        let calendar = try findList()
        let predicate = eventStore.predicateForReminders(in: [calendar])
        let reminderDataList = try await fetchReminderData(matching: predicate)

        // Get available sections
        let sections = Set(reminderDataList.compactMap { extractSection(from: $0.notes) })

        // Find matching section (case-insensitive) or use the provided status as-is
        let targetSection: String
        if let match = sections.first(where: { $0.lowercased() == status.lowercased() }) {
            targetSection = match
        } else {
            // If section doesn't exist yet, create it with the provided name
            targetSection = status
        }

        // Find the reminder
        let reminder = try findReminder(byTitle: id)

        // Update notes with new section
        let cleanedNotes = cleanNotes(reminder.notes) ?? ""
        reminder.notes = updateNotesWithSection(cleanedNotes, section: targetSection)

        try eventStore.save(reminder, commit: true)
    }

    /// Get all incomplete reminders from the configured list
    func fetchAllReminders() async throws -> [TaskIssue] {
        try await requestAccess()

        let calendar = try findList()
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: [calendar]
        )

        let reminderDataList = try await fetchReminderData(matching: predicate)

        return reminderDataList.map { data in
            TaskIssue(
                id: data.title ?? "Untitled",
                title: data.title ?? "Untitled",
                description: cleanNotes(data.notes)
            )
        }
    }

    /// Mark a reminder as completed
    func completeReminder(_ id: String) async throws {
        try await requestAccess()

        let reminder = try findReminder(byTitle: id)
        reminder.isCompleted = true
        reminder.completionDate = Date()

        try eventStore.save(reminder, commit: true)
    }

    /// Create a new reminder in the configured list
    func createReminder(title: String, notes: String?, dueDate: Date? = nil, section: String? = nil) async throws -> String {
        try await requestAccess()

        let calendar = try findList()

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title

        // Add section to notes if provided
        if let section = section {
            reminder.notes = updateNotesWithSection(notes, section: section)
        } else {
            reminder.notes = notes
        }

        reminder.calendar = calendar

        if let dueDate = dueDate {
            reminder.dueDateComponents = Foundation.Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        try eventStore.save(reminder, commit: true)

        return reminder.title ?? title
    }
}
