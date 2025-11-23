struct LinearResponse: Codable {
    let data: LinearData
}

struct LinearData: Codable {
    let issue: LinearIssue?
}

struct LinearIssue: Codable {
    let id: String
    let identifier: String
    let title: String
    let description: String?
}

struct LinearStatesResponse: Codable {
    let data: LinearStatesData
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
