import Foundation

public struct TitleSegment: Equatable {
    public let symbol: String
    public let text: String
    public let isError: Bool
    public init(symbol: String, text: String, isError: Bool = false) {
        self.symbol = symbol
        self.text = text
        self.isError = isError
    }
}

public struct SourceVisibility: Equatable {
    public let gitlab: Bool
    public let github: Bool
    public let jira: Bool
    public init(gitlab: Bool = true, github: Bool = false, jira: Bool = true) {
        self.gitlab = gitlab
        self.github = github
        self.jira = jira
    }
}

public enum StatusFormatter {
    public static let mrSymbol = "arrow.triangle.merge"
    public static let readySymbol = "checkmark.seal"
    public static let backlogSymbol = "tray.full"
    public static let inProgressSymbol = "bolt"
    public static let testingAwaitingSymbol = "hourglass"
    public static let testingMovedOnSymbol = "checkmark.diamond"
    public static let errorSymbol = "exclamationmark.triangle"
    public static let githubOpenSymbol = "arrow.triangle.pull"
    public static let githubReadySymbol = "checkmark.circle"

    static let errorText = "—"
    static let loadingText = "…"

    static func text(_ value: String?, hasError: Bool) -> String {
        if let value { return value }

        return hasError ? errorText : loadingText
    }

    private static func segment(symbol: String, value: String?, hasError: Bool) -> TitleSegment {
        if hasError {
            return TitleSegment(symbol: errorSymbol, text: text(value, hasError: hasError), isError: true)
        }

        return TitleSegment(symbol: symbol, text: text(value, hasError: hasError))
    }

    public static func segments(
        gitlab: SourceResult<GitLabCounts>,
        github: SourceResult<GitHubCounts> = .init(),
        jira: SourceResult<JiraCounts>,
        visibility: SourceVisibility = .init()
    ) -> [TitleSegment] {
        var result: [TitleSegment] = []

        if visibility.gitlab {
            let e = gitlab.error != nil
            result.append(segment(symbol: mrSymbol, value: gitlab.value.map { String($0.open) }, hasError: e))
            result.append(segment(symbol: readySymbol, value: gitlab.value.map { String($0.ready) }, hasError: e))
        }

        if visibility.github {
            let e = github.error != nil
            result.append(segment(symbol: githubOpenSymbol, value: github.value.map { String($0.open) }, hasError: e))
            result.append(segment(symbol: githubReadySymbol, value: github.value.map { String($0.approved) }, hasError: e))
        }

        if visibility.jira {
            let e = jira.error != nil
            result.append(segment(symbol: backlogSymbol, value: jira.value.map { String($0.backlog) }, hasError: e))
            result.append(segment(symbol: inProgressSymbol, value: jira.value.map { String($0.inProgress) }, hasError: e))
            result.append(segment(symbol: testingAwaitingSymbol, value: jira.value.map { String($0.testingAwaiting) }, hasError: e))
            result.append(segment(symbol: testingMovedOnSymbol, value: jira.value.map { String($0.testingMovedOn) }, hasError: e))
        }

        return result
    }

    public static func tooltip(
        gitlab: SourceResult<GitLabCounts>,
        github: SourceResult<GitHubCounts> = .init(),
        jira: SourceResult<JiraCounts>,
        lastRefresh: Date?,
        visibility: SourceVisibility = .init()
    ) -> String {
        var parts: [String] = []

        if visibility.gitlab {
            if let g = gitlab.value {
                parts.append("Moje MR: \(g.open) otwartych, \(g.ready) gotowe do mergu (≥2 approve)")
            }

            if let e = gitlab.error {
                parts.append("GitLab błąd: \(e)")
            }
        }

        if visibility.github {
            if let g = github.value {
                parts.append("GitHub: \(g.open) PR, \(g.approved) approved")
            }

            if let e = github.error {
                parts.append("GitHub błąd: \(e)")
            }
        }

        if visibility.jira {
            if let j = jira.value {
                parts.append("Jira: \(j.backlog) backlog, \(j.inProgress) w toku")
                parts.append("Testy: \(j.testingAwaiting) czeka, \(j.testingMovedOn) przetestowane")
            }

            if let e = jira.error {
                parts.append("Jira błąd: \(e)")
            }
        }

        if let last = lastRefresh {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            parts.append("odświeżono \(f.string(from: last))")
        }

        return parts.joined(separator: " · ")
    }
}
