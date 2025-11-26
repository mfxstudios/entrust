import Foundation

struct LinearTracker: TaskTracker {
    let token: String

    var baseURL: String { "https://api.linear.app" }

    func fetchIssue(_ id: String) async throws -> TaskIssue {
        let query = "query Issue($id: String!) { issue(id: $id) { id identifier title description }}"

        let payload: [String: Any] = [
            "query": query,
            "variables": ["id": id]
        ]

        var request = URLRequest(url: URL(string: "\(baseURL)/graphql")!)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        print("🔍 Linear API: Fetching issue '\(id)'...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
            throw AutomationError.issueFetchFailed
        }

        print("📡 Linear API Response: HTTP \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ HTTP Error \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response body: \(responseString)")
            }
            throw AutomationError.issueFetchFailed
        }

        // Print response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("📄 Response: \(responseString)")
        }

        let linearResponse = try JSONDecoder().decode(LinearResponse.self, from: data)

        // Check for GraphQL errors
        if let errors = linearResponse.errors, !errors.isEmpty {
            let errorMessage = errors.map { $0.message }.joined(separator: ", ")
            print("❌ Linear API Error: \(errorMessage)")
            throw AutomationError.issueFetchFailed
        }

        guard let data = linearResponse.data, let issue = data.issue else {
            print("❌ No issue data in response")
            throw AutomationError.issueNotFound
        }

        return TaskIssue(
            id: issue.identifier,
            title: issue.title,
            description: issue.description
        )
    }

    func updateIssue(_ id: String, prURL: String) async throws {
        let query = """
        mutation CommentCreate($issueId: String!, $body: String!) {
            commentCreate(input: {issueId: $issueId, body: $body}) {
                success
            }
        }
        """

        let payload: [String: Any] = [
            "query": query,
            "variables": [
                "issueId": id,
                "body": "🤖 Automated PR created: \(prURL)"
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AutomationError.issueUpdateFailed
        }
    }

    func getAvailableStatuses(_ id: String) async throws -> [IssueStatus] {
            let query = """
            query Issue($id: String!) {
                issue(id: $id) {
                    team {
                        states {
                            nodes {
                                id
                                name
                                description
                            }
                        }
                    }
                }
            }
            """

            let payload: [String: Any] = [
                "query": query,
                "variables": ["id": id]
            ]

            var request = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
            request.httpMethod = "POST"
            request.setValue(token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw AutomationError.statusFetchFailed
            }

            let statesResponse = try JSONDecoder().decode(LinearStatesResponse.self, from: data)

            // Check for GraphQL errors
            if let errors = statesResponse.errors, !errors.isEmpty {
                let errorMessage = errors.map { $0.message }.joined(separator: ", ")
                print("❌ Linear API Error: \(errorMessage)")
                throw AutomationError.statusFetchFailed
            }

            guard let data = statesResponse.data, let states = data.issue?.team.states.nodes else {
                throw AutomationError.issueNotFound
            }

            return states.map { state in
                IssueStatus(
                    id: state.id,
                    name: state.name,
                    description: state.description
                )
            }
        }

        func changeStatus(_ id: String, to status: String) async throws {
            // First, get available statuses
            let availableStatuses = try await getAvailableStatuses(id)

            // Find matching status (case-insensitive)
            guard let targetStatus = availableStatuses.first(where: {
                $0.name.lowercased() == status.lowercased()
            }) else {
                throw AutomationError.invalidStatus(status, available: availableStatuses.map { $0.name })
            }

            let query = """
            mutation IssueUpdate($issueId: String!, $stateId: String!) {
                issueUpdate(id: $issueId, input: {stateId: $stateId}) {
                    success
                }
            }
            """

            let payload: [String: Any] = [
                "query": query,
                "variables": [
                    "issueId": id,
                    "stateId": targetStatus.id
                ]
            ]

            var request = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
            request.httpMethod = "POST"
            request.setValue(token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw AutomationError.statusChangeFailed
            }
        }
}
