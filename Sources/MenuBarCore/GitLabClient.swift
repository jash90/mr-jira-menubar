import Foundation

public protocol GitLabFetching: Sendable {
    func fetchOpenMRCount() async throws -> Int
    func fetchReadyToMergeCount() async throws -> Int
}

public enum GitLabError: Error, Equatable, CustomStringConvertible {
    case badResponse
    case missingTotal
    case status(Int)

    public var description: String {
        switch self {
        case .badResponse: return "GitLab: nieprawidłowa odpowiedź serwera"
        case .missingTotal: return "GitLab: brak nagłówka X-Total"
        case .status(let code):
            return code == 401
                ? "GitLab 401 — token wygasł lub został zmieniony"
                : "GitLab HTTP \(code)"
        }
    }
}

public protocol MergeRequestLookup: Sendable {
    func hasMyMergeRequest(referencing key: String, createdBefore: Date) async throws -> Bool
}

public struct GitLabClient: GitLabFetching, MergeRequestLookup, Sendable {
    public let host: String
    let token: String
    let session: URLSession
    let approvalThreshold: Int

    public init(host: String, token: String, session: URLSession = .shared, approvalThreshold: Int = 2) {
        self.host = normalizedHost(host)
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

    static let createdBeforeFormatter = ISO8601DateFormatter()

    public func hasMyMergeRequest(referencing key: String, createdBefore: Date) async throws -> Bool {
        let req = request("/merge_requests", query: [
            .init(name: "scope", value: "created_by_me"),
            .init(name: "state", value: "all"),
            .init(name: "search", value: key),
            .init(name: "created_before", value: Self.createdBeforeFormatter.string(from: createdBefore)),
            .init(name: "per_page", value: "1"),
        ])
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GitLabError.badResponse }
        guard http.statusCode == 200 else { throw GitLabError.status(http.statusCode) }
        guard let total = http.value(forHTTPHeaderField: "X-Total"), let n = Int(total) else {
            throw GitLabError.missingTotal
        }
        return n > 0
    }

    struct MRRef: Decodable { let project_id: Int; let iid: Int }
    struct Approvals: Decodable { let approved_by: [ApprovedBy] }
    struct ApprovedBy: Decodable {}

    public func fetchReadyToMergeCount() async throws -> Int {
        let mrs = try await fetchMyOpenMRs()
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            for mr in mrs {
                group.addTask { try await self.isReady(mr) }
            }
            var count = 0
            for try await ready in group where ready { count += 1 }
            return count
        }
    }

    func fetchMyOpenMRs() async throws -> [MRRef] {
        var page = 1
        var result: [MRRef] = []
        while true {
            let req = request("/merge_requests", query: [
                .init(name: "scope", value: "created_by_me"),
                .init(name: "state", value: "opened"),
                .init(name: "per_page", value: "100"),
                .init(name: "page", value: String(page)),
            ])
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw GitLabError.badResponse }
            guard http.statusCode == 200 else { throw GitLabError.status(http.statusCode) }
            result.append(contentsOf: try JSONDecoder().decode([MRRef].self, from: data))
            guard let next = http.value(forHTTPHeaderField: "X-Next-Page"),
                  !next.isEmpty, let np = Int(next) else { break }
            page = np
        }
        return result
    }

    func isReady(_ mr: MRRef) async throws -> Bool {
        let req = request("/projects/\(mr.project_id)/merge_requests/\(mr.iid)/approvals", query: [])
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GitLabError.badResponse }
        guard http.statusCode == 200 else { throw GitLabError.status(http.statusCode) }
        return try JSONDecoder().decode(Approvals.self, from: data).approved_by.count >= approvalThreshold
    }
}
