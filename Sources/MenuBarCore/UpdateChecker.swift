import Foundation

public enum SemVer {
    /// True when `candidate` is a strictly higher version than `current`.
    /// Tolerates a leading "v" and differing component counts (missing = 0).
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate)
        let b = components(current)

        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0

            if x != y { return x > y }
        }

        return false
    }

    private static func components(_ raw: String) -> [Int] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        return stripped.split(separator: ".").map { Int($0) ?? 0 }
    }
}

public struct ReleaseInfo: Equatable, Sendable {
    public let version: String
    public let tag: String
    public let dmgURL: URL?
    public let htmlURL: URL?

    public init(version: String, tag: String, dmgURL: URL?, htmlURL: URL?) {
        self.version = version
        self.tag = tag
        self.dmgURL = dmgURL
        self.htmlURL = htmlURL
    }
}

public enum UpdateError: Error, Equatable, CustomStringConvertible {
    case badResponse
    case status(Int)

    public var description: String {
        switch self {
        case .badResponse: return "Aktualizacja: niepoprawna odpowiedź"
        case .status(let code): return "Aktualizacja: błąd HTTP \(code)"
        }
    }
}

public protocol ReleaseFetching: Sendable {
    func fetchLatestRelease() async throws -> ReleaseInfo
}

public struct GitHubReleaseClient: ReleaseFetching, Sendable {
    public static let owner = "jash90"
    public static let repo = "mr-jira-menubar"

    let token: String?
    let session: URLSession

    public init(token: String? = nil, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    private struct Asset: Decodable { let name: String; let browser_download_url: String }
    private struct Release: Decodable { let tag_name: String; let html_url: String?; let assets: [Asset] }

    public func fetchLatestRelease() async throws -> ReleaseInfo {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "api.github.com"
        comps.path = "/repos/\(Self.owner)/\(Self.repo)/releases/latest"
        guard let url = comps.url else { throw UpdateError.badResponse }

        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("MRJiraMenuBar", forHTTPHeaderField: "User-Agent")

        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse }
        guard http.statusCode == 200 else { throw UpdateError.status(http.statusCode) }

        let release = try JSONDecoder().decode(Release.self, from: data)
        let tag = release.tag_name
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }

        return ReleaseInfo(
            version: version,
            tag: tag,
            dmgURL: dmg.flatMap { URL(string: $0.browser_download_url) },
            htmlURL: release.html_url.flatMap(URL.init(string:))
        )
    }
}

@MainActor
public final class UpdateChecker {
    public private(set) var availableUpdate: ReleaseInfo?
    public var onUpdate: (@MainActor () -> Void)?

    private let client: ReleaseFetching
    private let currentVersion: String

    public init(client: ReleaseFetching, currentVersion: String) {
        self.client = client
        self.currentVersion = currentVersion
    }

    public func check() async {
        do {
            let latest = try await client.fetchLatestRelease()
            availableUpdate = SemVer.isNewer(latest.version, than: currentVersion) ? latest : nil
        } catch {
            // Update checks are best-effort — a failed fetch must not disrupt the app.
        }

        onUpdate?()
    }
}
