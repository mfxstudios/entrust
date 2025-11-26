struct LinearResponse: Codable {
    let data: LinearData?
    let errors: [LinearError]?
}

struct LinearError: Codable {
    let message: String
    let extensions: LinearErrorExtensions?
}

struct LinearErrorExtensions: Codable {
    let code: String?
}

struct LinearData: Codable {
    let issue: LinearIssue?
    let issues: LinearIssuesConnection?
}

struct LinearIssuesConnection: Codable {
    let nodes: [LinearIssue]
}

struct LinearIssue: Codable {
    let id: String
    let identifier: String
    let title: String
    let description: String?
}

struct LinearStatesResponse: Codable {
    let data: LinearStatesData?
    let errors: [LinearError]?
}

struct LinearStatesData: Codable {
    let issue: LinearIssueWithStates?
}

struct LinearIssueWithStates: Codable {
    let team: LinearTeam
}

struct LinearTeam: Codable {
    let states: LinearStates
}

struct LinearStates: Codable {
    let nodes: [LinearState]
}

struct LinearState: Codable {
    let id: String
    let name: String
    let description: String?
}
