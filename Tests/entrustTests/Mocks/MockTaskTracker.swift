import Foundation
@testable import entrust

/// A mock TaskTracker for testing purposes
actor MockTaskTracker: TaskTracker, @unchecked Sendable {
    nonisolated var baseURL: String { "https://mock.tracker.test" }

    // MARK: - Stored Data
    private var issues: [String: TaskIssue] = [:]
    private var statuses: [String: String] = [:]  // issueId -> status
    private var availableStatuses: [IssueStatus] = []
    private var comments: [String: [String]] = [:]  // issueId -> comments

    // MARK: - Call Tracking
    private(set) var fetchIssueCalls: [String] = []
    private(set) var updateIssueCalls: [(id: String, prURL: String)] = []
    private(set) var changeStatusCalls: [(id: String, status: String)] = []
    private(set) var getAvailableStatusesCalls: [String] = []

    // MARK: - Error Simulation
    var shouldFailFetchIssue = false
    var shouldFailUpdateIssue = false
    var shouldFailChangeStatus = false
    var shouldFailGetAvailableStatuses = false

    // MARK: - Setup Methods

    func givenIssueExists(_ issue: TaskIssue) {
        issues[issue.id] = issue
    }

    func givenIssueExists(id: String, title: String, description: String?) {
        issues[id] = TaskIssue(id: id, title: title, description: description)
    }

    func givenIssueHasStatus(_ issueId: String, status: String) {
        statuses[issueId] = status
    }

    func givenAvailableStatuses(_ statuses: [IssueStatus]) {
        self.availableStatuses = statuses
    }

    func givenAvailableStatuses(_ names: [String]) {
        self.availableStatuses = names.enumerated().map { index, name in
            IssueStatus(id: "status-\(index)", name: name, description: nil)
        }
    }

    // MARK: - TaskTracker Protocol

    nonisolated func fetchIssue(_ id: String) async throws -> TaskIssue {
        await recordFetchIssueCall(id)

        if await shouldFailFetchIssue {
            throw AutomationError.issueFetchFailed
        }

        guard let issue = await getIssue(id) else {
            throw AutomationError.issueNotFound
        }

        return issue
    }

    nonisolated func updateIssue(_ id: String, prURL: String) async throws {
        await recordUpdateIssueCall(id: id, prURL: prURL)

        if await shouldFailUpdateIssue {
            throw AutomationError.issueUpdateFailed
        }

        guard await getIssue(id) != nil else {
            throw AutomationError.issueNotFound
        }

        await addComment(issueId: id, comment: "PR: \(prURL)")
    }

    nonisolated func changeStatus(_ id: String, to status: String) async throws {
        await recordChangeStatusCall(id: id, status: status)

        if await shouldFailChangeStatus {
            throw AutomationError.statusChangeFailed
        }

        let available = await getAvailableStatusNames()
        guard available.map({ $0.lowercased() }).contains(status.lowercased()) else {
            throw AutomationError.invalidStatus(status, available: available)
        }

        await setStatus(issueId: id, status: status)
    }

    nonisolated func getAvailableStatuses(_ id: String) async throws -> [IssueStatus] {
        await recordGetAvailableStatusesCall(id)

        if await shouldFailGetAvailableStatuses {
            throw AutomationError.statusFetchFailed
        }

        return await getAllAvailableStatuses()
    }

    // MARK: - Private Actor Methods

    private func recordFetchIssueCall(_ id: String) {
        fetchIssueCalls.append(id)
    }

    private func recordUpdateIssueCall(id: String, prURL: String) {
        updateIssueCalls.append((id: id, prURL: prURL))
    }

    private func recordChangeStatusCall(id: String, status: String) {
        changeStatusCalls.append((id: id, status: status))
    }

    private func recordGetAvailableStatusesCall(_ id: String) {
        getAvailableStatusesCalls.append(id)
    }

    private func getIssue(_ id: String) -> TaskIssue? {
        issues[id]
    }

    private func addComment(issueId: String, comment: String) {
        if comments[issueId] == nil {
            comments[issueId] = []
        }
        comments[issueId]?.append(comment)
    }

    private func setStatus(issueId: String, status: String) {
        statuses[issueId] = status
    }

    private func getAvailableStatusNames() -> [String] {
        availableStatuses.map { $0.name }
    }

    private func getAllAvailableStatuses() -> [IssueStatus] {
        availableStatuses
    }

    // MARK: - Verification Methods

    func getStatus(for issueId: String) -> String? {
        statuses[issueId]
    }

    func getComments(for issueId: String) -> [String] {
        comments[issueId] ?? []
    }

    func verifyFetchIssueWasCalled(with id: String) -> Bool {
        fetchIssueCalls.contains(id)
    }

    func verifyUpdateIssueWasCalled(with id: String, prURL: String) -> Bool {
        updateIssueCalls.contains { $0.id == id && $0.prURL == prURL }
    }

    func verifyChangeStatusWasCalled(with id: String, to status: String) -> Bool {
        changeStatusCalls.contains { $0.id == id && $0.status == status }
    }

    func reset() {
        issues.removeAll()
        statuses.removeAll()
        availableStatuses.removeAll()
        comments.removeAll()
        fetchIssueCalls.removeAll()
        updateIssueCalls.removeAll()
        changeStatusCalls.removeAll()
        getAvailableStatusesCalls.removeAll()
        shouldFailFetchIssue = false
        shouldFailUpdateIssue = false
        shouldFailChangeStatus = false
        shouldFailGetAvailableStatuses = false
    }
}
