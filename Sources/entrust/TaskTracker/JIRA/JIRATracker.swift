//
//  JIRATracker.swift
//  entrust
//
//  Created by Prince Ugwuh on 11/22/25.
//

import Foundation

struct JIRATracker: TaskTracker {
    let url: String
    let email: String
    let token: String

    var baseURL: String { url }

    func fetchIssue(_ id: String) async throws -> TaskIssue {
        var request = URLRequest(url: URL(string: "\(url)/rest/api/3/issue/\(id)")!)

        let credentials = "\(email):\(token)"
        let credentialData = credentials.data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()

        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AutomationError.issueFetchFailed
        }

        let jiraIssue = try JSONDecoder().decode(JIRAIssue.self, from: data)

        return TaskIssue(
            id: jiraIssue.key,
            title: jiraIssue.fields.summary,
            description: jiraIssue.fields.description
        )
    }

    func updateIssue(_ id: String, prURL: String) async throws {
        var request = URLRequest(
            url: URL(string: "\(url)/rest/api/3/issue/\(id)/comment")!
        )
        request.httpMethod = "POST"

        let credentials = "\(email):\(token)"
        let credentialData = credentials.data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()

        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let comment = JIRAComment(body: .init(
            type: "doc",
            version: 1,
            content: [
                .init(
                    type: "paragraph",
                    content: [
                        .init(type: "text", text: "🤖 Automated PR created: \(prURL)")
                    ]
                )
            ]
        ))

        request.httpBody = try JSONEncoder().encode(comment)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AutomationError.issueUpdateFailed
        }
    }

    func getAvailableStatuses(_ id: String) async throws -> [IssueStatus] {
            var request = URLRequest(
                url: URL(string: "\(url)/rest/api/3/issue/\(id)/transitions")!
            )

            let credentials = "\(email):\(token)"
            let credentialData = credentials.data(using: .utf8)!
            let base64Credentials = credentialData.base64EncodedString()

            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw AutomationError.statusFetchFailed
            }

            let transitionsResponse = try JSONDecoder().decode(JIRATransitionsResponse.self, from: data)

            return transitionsResponse.transitions.map { transition in
                IssueStatus(
                    id: transition.id,
                    name: transition.name,
                    description: nil
                )
            }
        }

    func changeStatus(_ id: String, to status: String) async throws {
            // First, get available transitions
            let availableStatuses = try await getAvailableStatuses(id)

            // Find matching transition (case-insensitive)
            guard let targetStatus = availableStatuses.first(where: {
                $0.name.lowercased() == status.lowercased()
            }) else {
                throw AutomationError.invalidStatus(status, available: availableStatuses.map { $0.name })
            }

            // Execute transition
            var request = URLRequest(
                url: URL(string: "\(url)/rest/api/3/issue/\(id)/transitions")!
            )
            request.httpMethod = "POST"

            let credentials = "\(email):\(token)"
            let credentialData = credentials.data(using: .utf8)!
            let base64Credentials = credentialData.base64EncodedString()

            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload: [String: Any] = [
                "transition": ["id": targetStatus.id]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw AutomationError.statusChangeFailed
            }
        }
}
