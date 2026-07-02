import Foundation

public protocol JiraFetching: Sendable {
    func backlogCount() async throws -> Int
    func inProgressCount() async throws -> Int
    func testingAwaitingCount() async throws -> Int
    func testingAcceptedCount() async throws -> Int
    func testingRejectedCount() async throws -> Int
}

public enum JiraError: Error, Equatable, CustomStringConvertible {
    case badResponse
    case status(Int)

    public var description: String {
        switch self {
        case .badResponse: return "Jira: nieprawidłowa odpowiedź serwera"
        case .status(let code):
            return code == 401
                ? "Jira 401 — token wygasł lub został zmieniony"
                : "Jira HTTP \(code)"
        }
    }
}

public struct StatusTransition: Equatable, Sendable {
    public let author: String
    public let toStatus: String
    public init(author: String, toStatus: String) {
        self.author = author
        self.toStatus = toStatus
    }
}

public struct JiraClient: JiraFetching, Sendable {
    public static let backlogJQL =
        #"assignee = currentUser() AND resolution = Unresolved AND status in ("To Do", "Backlog")"#
    public static let inProgressJQL =
        #"assignee = currentUser() AND resolution = Unresolved AND status = "In Progress""#
    public static let testingStatus = "Internal testing"
    public static let reviewStatus = "Code review"
    // "My" tickets need both signals: the move to testing may be clicked by someone else
    // (then only assignee matches), and after acceptance the assignee changes
    // (then only the transition author matches).
    static let myTestedIssues =
        #"(assignee = currentUser() OR status CHANGED TO "Internal testing" BY currentUser()) AND status CHANGED TO "Internal testing""#
    // Rejected = sent back to a pre-testing status; accepted = moved forward
    // (Acceptance, Accepted, Done, …) — testers accept via "Acceptance", not straight to Done.
    static let preTestingStatuses = #""Backlog", "To Do", "New", "In Progress", "Code review""#
    public static let testingAwaitingJQL =
        myTestedIssues + #" AND status = "Internal testing""#
    public static let testingAcceptedJQL =
        myTestedIssues + #" AND status not in ("Internal testing", "# + preTestingStatuses + ")"
    public static let testingRejectedJQL =
        myTestedIssues + " AND status in (" + preTestingStatuses + ")"

    public let host: String
    let token: String
    let session: URLSession

    public init(host: String, token: String, session: URLSession = .shared) {
        self.host = normalizedHost(host)
        self.token = token
        self.session = session
    }

    struct SearchResult: Decodable { let total: Int }

    struct MyselfResult: Decodable { let name: String }

    struct ChangelogSearchResult: Decodable {
        let issues: [Issue]

        struct Issue: Decodable { let changelog: Changelog }
        struct Changelog: Decodable { let histories: [History] }
        struct History: Decodable { let author: Author; let items: [Item] }
        struct Author: Decodable { let name: String }
        struct Item: Decodable {
            let field: String
            let to: String?
            enum CodingKeys: String, CodingKey {
                case field
                case to = "toString"
            }
        }
    }

    func get(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = path
        comps.queryItems = queryItems
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw JiraError.badResponse }
        guard http.statusCode == 200 else { throw JiraError.status(http.statusCode) }
        return data
    }

    public func count(jql: String) async throws -> Int {
        let data = try await get(path: "/rest/api/2/search", queryItems: [
            .init(name: "jql", value: jql),
            .init(name: "maxResults", value: "0"),
        ])
        return try JSONDecoder().decode(SearchResult.self, from: data).total
    }

    func myself() async throws -> String {
        let data = try await get(path: "/rest/api/2/myself", queryItems: [])
        return try JSONDecoder().decode(MyselfResult.self, from: data).name
    }

    func searchTransitions(jql: String) async throws -> [[StatusTransition]] {
        let data = try await get(path: "/rest/api/2/search", queryItems: [
            .init(name: "jql", value: jql),
            .init(name: "expand", value: "changelog"),
            .init(name: "fields", value: "status"),
            .init(name: "maxResults", value: "100"),
        ])
        let result = try JSONDecoder().decode(ChangelogSearchResult.self, from: data)
        return result.issues.map { issue in
            issue.changelog.histories.flatMap { history in
                history.items.compactMap { item -> StatusTransition? in
                    guard item.field == "status", let to = item.to else { return nil }

                    return StatusTransition(author: history.author.name, toStatus: to)
                }
            }
        }
    }

    // JQL cannot see who developed the tested round (a takeover after rejection would count
    // the previous developer's rejection as mine), so the final filter runs on the changelog.
    public static func developerOfLastTestingRound(_ transitions: [StatusTransition]) -> String? {
        guard let lastTestingIndex = transitions.lastIndex(where: { $0.toStatus == testingStatus }) else { return nil }

        let beforeTesting = transitions[..<lastTestingIndex]

        if let lastReview = beforeTesting.last(where: { $0.toStatus == reviewStatus }) {
            return lastReview.author
        }

        return transitions[lastTestingIndex].author
    }

    func myDevelopedCount(jql: String) async throws -> Int {
        async let me = myself()
        async let transitionsPerIssue = searchTransitions(jql: jql)
        let developer = try await me
        return try await transitionsPerIssue
            .filter { Self.developerOfLastTestingRound($0) == developer }
            .count
    }

    public func backlogCount() async throws -> Int { try await count(jql: Self.backlogJQL) }
    public func inProgressCount() async throws -> Int { try await count(jql: Self.inProgressJQL) }
    public func testingAwaitingCount() async throws -> Int { try await count(jql: Self.testingAwaitingJQL) }
    public func testingAcceptedCount() async throws -> Int { try await myDevelopedCount(jql: Self.testingAcceptedJQL) }
    public func testingRejectedCount() async throws -> Int { try await myDevelopedCount(jql: Self.testingRejectedJQL) }
}
