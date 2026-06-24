import Foundation

public protocol JiraFetching {
    func backlogCount() async throws -> Int
    func inProgressCount() async throws -> Int
}

public enum JiraError: Error, Equatable {
    case badResponse
}

public struct JiraClient: JiraFetching {
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
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw JiraError.badResponse
        }
        return try JSONDecoder().decode(SearchResult.self, from: data).total
    }

    public func backlogCount() async throws -> Int { try await count(jql: Self.backlogJQL) }
    public func inProgressCount() async throws -> Int { try await count(jql: Self.inProgressJQL) }
}
