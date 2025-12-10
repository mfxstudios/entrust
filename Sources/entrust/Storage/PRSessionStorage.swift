import Foundation

/// Information about a PR session that can be continued
struct PRSessionInfo: Codable, Sendable {
    var sessionId: String
    let ticketId: String
    let branch: String
    let createdAt: Date
    let skipTests: Bool
    var lastProcessedComments: [Int]

    init(
        sessionId: String,
        ticketId: String,
        branch: String,
        createdAt: Date = Date(),
        skipTests: Bool = false,
        lastProcessedComments: [Int] = []
    ) {
        self.sessionId = sessionId
        self.ticketId = ticketId
        self.branch = branch
        self.createdAt = createdAt
        self.skipTests = skipTests
        self.lastProcessedComments = lastProcessedComments
    }
}

/// Manages storage of PR session information for feedback continuation
struct PRSessionStorage: Sendable {
    private let fileURL: URL

    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let entrustDirectory = homeDirectory.appendingPathComponent(".entrust")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(
            at: entrustDirectory,
            withIntermediateDirectories: true
        )

        self.fileURL = entrustDirectory.appendingPathComponent("pr-sessions.json")
    }

    /// Save session info for a PR URL
    func save(prURL: String, sessionInfo: PRSessionInfo) throws {
        var sessions = try loadAll()
        sessions[prURL] = sessionInfo
        try saveAll(sessions)
    }

    /// Get session info for a PR URL
    func get(prURL: String) throws -> PRSessionInfo? {
        let sessions = try loadAll()
        return sessions[prURL]
    }

    /// Update processed comments for a PR
    func updateProcessedComments(prURL: String, commentIDs: [Int]) throws {
        var sessions = try loadAll()
        guard var sessionInfo = sessions[prURL] else {
            throw AutomationError.configurationNotFound
        }

        // Add new comment IDs to the list
        sessionInfo.lastProcessedComments.append(contentsOf: commentIDs)
        sessions[prURL] = sessionInfo
        try saveAll(sessions)
    }

    /// Update session ID for a PR (when conversation is continued)
    func updateSessionId(prURL: String, newSessionId: String) throws {
        var sessions = try loadAll()
        guard var sessionInfo = sessions[prURL] else {
            throw AutomationError.configurationNotFound
        }

        sessionInfo.sessionId = newSessionId
        sessions[prURL] = sessionInfo
        try saveAll(sessions)
    }

    /// Load all sessions
    private func loadAll() throws -> [String: PRSessionInfo] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: PRSessionInfo].self, from: data)
    }

    /// Save all sessions
    private func saveAll(_ sessions: [String: PRSessionInfo]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(sessions)
        try data.write(to: fileURL)
    }

    /// Extract session ID from PR description (fallback if not in local storage)
    func extractSessionFromPRDescription(_ description: String) -> String? {
        // Look for <!-- entrust-session: abc123 -->
        let pattern = "<!--\\s*entrust-session:\\s*([a-zA-Z0-9-]+)\\s*-->"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsDescription = description as NSString
        let matches = regex.matches(in: description, range: NSRange(location: 0, length: nsDescription.length))

        guard let match = matches.first,
              match.numberOfRanges > 1 else {
            return nil
        }

        let sessionRange = match.range(at: 1)
        return nsDescription.substring(with: sessionRange)
    }

    /// Generate PR description footer with session ID
    static func generatePRDescriptionFooter(sessionId: String) -> String {
        "\n\n<!-- entrust-session: \(sessionId) -->"
    }
}
