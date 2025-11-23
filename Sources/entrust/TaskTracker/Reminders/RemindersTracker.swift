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
            description: data.notes
        )
    }

    func updateIssue(_ id: String, prURL: String) async throws {
        try await requestAccess()

        let reminder = try findReminder(byTitle: id)

        // Append PR URL to notes
        let existingNotes = reminder.notes ?? ""
        let separator = existingNotes.isEmpty ? "" : "\n\n"
        reminder.notes = "\(existingNotes)\(separator)🤖 Automated PR: \(prURL)"

        try eventStore.save(reminder, commit: true)
    }

    func getAvailableStatuses(_ id: String) async throws -> [IssueStatus] {
        // Reminders doesn't have built-in statuses like Kanban boards,
        // but we can use lists as pseudo-statuses for the column view.
        // Return common workflow statuses that map to reminder states.
        try await requestAccess()

        let calendars = eventStore.calendars(for: .reminder)

        // Return all reminder lists as possible "statuses" (columns)
        return calendars.map { calendar in
            IssueStatus(
                id: calendar.calendarIdentifier,
                name: calendar.title,
                description: nil
            )
        }
    }

    func changeStatus(_ id: String, to status: String) async throws {
        try await requestAccess()

        // Find the target list (status = list name)
        let calendars = eventStore.calendars(for: .reminder)
        guard let targetCalendar = calendars.first(where: {
            $0.title.lowercased() == status.lowercased()
        }) else {
            throw AutomationError.invalidStatus(
                status,
                available: calendars.map { $0.title }
            )
        }

        // Find the reminder
        let reminder = try findReminder(byTitle: id)

        // Move to new list by changing calendar
        reminder.calendar = targetCalendar

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
                description: data.notes
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
    func createReminder(title: String, notes: String?, dueDate: Date? = nil) async throws -> String {
        try await requestAccess()

        let calendar = try findList()

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
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
