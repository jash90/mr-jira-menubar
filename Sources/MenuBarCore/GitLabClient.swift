import Foundation

public protocol GitLabFetching {
    func fetchOpenMRCount() async throws -> Int
    func fetchReadyToMergeCount() async throws -> Int
}

public enum GitLabError: Error, Equatable {
    case badResponse
    case missingTotal
    case status(Int)
}

public struct GitLabClient: GitLabFetching {
    public let host: String
    let token: String
    let session: URLSession
    let approvalThreshold: Int

    public init(host: String, token: String, session: URLSession = .shared, approvalThreshold: Int = 2) {
        self.host = host
        self.token = token
        self.session = session
        self.approvalThreshold = approvalThreshold
    }

    func request(_ path: String, query: [URLQueryItem]) -> URLRequest {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = "/api/v4" + path
        comps.queryItems = query.isEmpty ? nil : query
        var req = URLRequest(url: comps.url!)
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        return req
    }

    public func fetchOpenMRCount() async throws -> Int {
        let req = request("/merge_requests", query: [
            .init(name: "scope", value: "created_by_me"),
            .init(name: "state", value: "opened"),
            .init(name: "per_page", value: "1"),
        ])
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GitLabError.badResponse }
        guard http.statusCode == 200 else { throw GitLabError.status(http.statusCode) }
        guard let total = http.value(forHTTPHeaderField: "X-Total"), let n = Int(total) else {
            throw GitLabError.missingTotal
        }
        return n
    }

    public func fetchReadyToMergeCount() async throws -> Int {
        // Implemented in Task 3.
        0
    }
}
