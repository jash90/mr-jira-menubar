import Foundation

public protocol JiraFetching: Sendable {
    func backlogCount() async throws -> Int
    func inProgressCount() async throws -> Int
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

public struct JiraClient: JiraFetching, Sendable {
    public static let backlogJQL =
        #"assignee = currentUser() AND resolution = Unresolved AND status in ("To Do", "Backlog")"#
    public static let inProgressJQL =
        #"assignee = currentUser() AND resolution = Unresolved AND status = "In Progress""#

    public let host: String
    let token: String
    let session: URLSession

    public init(host: String, token: String, session: URLSession = .shared) {
        self.host = host
        self.token = token
        self.session = session
    }

    struct SearchResult: Decodable { let total: Int }

    public func count(jql: String) async throws -> Int {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = "/rest/api/2/search"
        comps.queryItems = [
            .init(name: "jql", value: jql),
            .init(name: "maxResults", value: "0"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw JiraError.badResponse }
        guard http.statusCode == 200 else { throw JiraError.status(http.statusCode) }
        return try JSONDecoder().decode(SearchResult.self, from: data).total
    }

    public func backlogCount() async throws -> Int { try await count(jql: Self.backlogJQL) }
    public func inProgressCount() async throws -> Int { try await count(jql: Self.inProgressJQL) }
}
