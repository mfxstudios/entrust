struct JIRAIssue: Codable {
    let key: String
    let fields: Fields

    struct Fields: Codable {
        let summary: String
        let description: String?

        // Custom decoding to handle both plain text and ADF format
        enum CodingKeys: String, CodingKey {
            case summary
            case description
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            summary = try container.decode(String.self, forKey: .summary)

            // Try to decode description as String first (older JIRA API)
            if let plainText = try? container.decode(String.self, forKey: .description) {
                description = plainText
            }
            // Otherwise try to decode as ADF and extract text (newer JIRA API)
            else if let adf = try? container.decode(ADFDocument.self, forKey: .description) {
                description = adf.extractPlainText()
            }
            // If both fail, description is nil
            else {
                description = nil
            }
        }
    }

    /// Atlassian Document Format (ADF) structure
    struct ADFDocument: Codable {
        let type: String
        let version: Int
        let content: [ADFContent]?

        func extractPlainText() -> String {
            guard let content = content else { return "" }
            return content.compactMap { $0.extractPlainText() }.joined(separator: "\n")
        }
    }

    struct ADFContent: Codable {
        let type: String
        let content: [ADFTextNode]?
        let text: String?

        func extractPlainText() -> String {
            if let text = text {
                return text
            }
            if let content = content {
                return content.compactMap { $0.extractPlainText() }.joined(separator: "")
            }
            return ""
        }
    }

    struct ADFTextNode: Codable {
        let type: String
        let text: String?

        func extractPlainText() -> String {
            return text ?? ""
        }
    }
}

struct JIRAComment: Codable {
    let body: Body

    struct Body: Codable {
        let type: String
        let version: Int
        let content: [Content]
    }

    struct Content: Codable {
        let type: String
        let content: [TextContent]
    }

    struct TextContent: Codable {
        let type: String
        let text: String
    }
}

struct JIRATransitionsResponse: Codable {
    let transitions: [JIRATransition]
}

struct JIRATransition: Codable {
    let id: String
    let name: String
}
