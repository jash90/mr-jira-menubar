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

public enum StatusFormatter {
    public static let mrSymbol = "arrow.triangle.merge"
    public static let readySymbol = "checkmark.seal"
    public static let backlogSymbol = "tray.full"
    public static let inProgressSymbol = "bolt"
    public static let errorSymbol = "exclamationmark.triangle"

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

    public static func segments(gitlab: SourceResult<GitLabCounts>, jira: SourceResult<JiraCounts>) -> [TitleSegment] {
        let glError = gitlab.error != nil
        let jiraError = jira.error != nil
        return [
            segment(symbol: mrSymbol, value: gitlab.value.map { String($0.open) }, hasError: glError),
            segment(symbol: readySymbol, value: gitlab.value.map { String($0.ready) }, hasError: glError),
            segment(symbol: backlogSymbol, value: jira.value.map { String($0.backlog) }, hasError: jiraError),
            segment(symbol: inProgressSymbol, value: jira.value.map { String($0.inProgress) }, hasError: jiraError),
        ]
    }

    public static func tooltip(
        gitlab: SourceResult<GitLabCounts>,
        jira: SourceResult<JiraCounts>,
        lastRefresh: Date?
    ) -> String {
        var parts: [String] = []

        if let g = gitlab.value {
            parts.append("Moje MR: \(g.open) otwartych, \(g.ready) gotowe do mergu (≥2 approve)")
        }

        if let e = gitlab.error {
            parts.append("GitLab błąd: \(e)")
        }

        if let j = jira.value {
            parts.append("Jira: \(j.backlog) backlog, \(j.inProgress) w toku")
        }

        if let e = jira.error {
            parts.append("Jira błąd: \(e)")
        }

        if let last = lastRefresh {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            parts.append("odświeżono \(f.string(from: last))")
        }

        return parts.joined(separator: " · ")
    }
}
