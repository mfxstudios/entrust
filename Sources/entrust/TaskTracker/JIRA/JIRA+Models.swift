//
//  JIRAIssue.swift
//  entrust
//
//  Created by Prince Ugwuh on 11/22/25.
//


struct JIRAIssue: Codable {
    let key: String
    let fields: Fields

    struct Fields: Codable {
        let summary: String
        let description: String?
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
