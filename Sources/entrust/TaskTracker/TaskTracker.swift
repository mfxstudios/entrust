protocol TaskTracker: Sendable {
    func fetchIssue(_ id: String) async throws -> TaskIssue
    func updateIssue(_ id: String, prURL: String) async throws
    func changeStatus(_ id: String, to status: String) async throws
    func getAvailableStatuses(_ id: String) async throws -> [IssueStatus]
    var baseURL: String { get }
}
