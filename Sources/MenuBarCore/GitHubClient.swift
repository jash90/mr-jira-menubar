import Foundation

public protocol GitHubFetching: Sendable {
    func fetchOpenPRCount() async throws -> Int
    func fetchApprovedPRCount() async throws -> Int
}

public enum GitHubError: Error, Equatable, CustomStringConvertible {
    case badResponse
    case status(Int)

    public var description: String {
        switch self {
        case .badResponse: return "GitHub: niepoprawna odpowiedź"
        case .status(401): return "GitHub: token wygasł lub jest niepoprawny (401)"
        case .status(403): return "GitHub: brak dostępu lub limit zapytań (403)"
        case .status(let code): return "GitHub: błąd HTTP \(code)"
        }
    }
}

public struct GitHubClient: GitHubFetching, Sendable {
    public let host: String
    let token: String
    let session: URLSession

    public init(host: String = "api.github.com", token: String, session: URLSession = .shared) {
        self.host = Self.normalizeHost(host)
        self.token = token
        self.session = session
    }

    static func normalizeHost(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutScheme = trimmed
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        let bare = withoutScheme.split(separator: "/").first.map(String.init) ?? withoutScheme

        if bare == "github.com" || bare == "www.github.com" {
            return "api.github.com"
        }

        return bare
    }

    static let openQuery = "is:pr is:open author:@me archived:false"
    static let approvedQuery = "is:pr is:open author:@me archived:false review:approved"

    public func fetchOpenPRCount() async throws -> Int { try await count(query: Self.openQuery) }
    public func fetchApprovedPRCount() async throws -> Int { try await count(query: Self.approvedQuery) }

    private var basePath: String { host == "api.github.com" ? "" : "/api/v3" }

    struct SearchResult: Decodable { let total_count: Int }

    private func count(query: String) async throws -> Int {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = basePath + "/search/issues"
        comps.queryItems = [
            .init(name: "q", value: query),
            .init(name: "per_page", value: "1"),
        ]
        guard let url = comps.url else { throw GitHubError.badResponse }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("MRJiraMenuBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.badResponse }
        guard http.statusCode == 200 else { throw GitHubError.status(http.statusCode) }
        return try JSONDecoder().decode(SearchResult.self, from: data).total_count
    }
}
