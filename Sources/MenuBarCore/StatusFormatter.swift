import Foundation

public struct TitleSegment: Equatable {
    public let symbol: String
    public let text: String
    public init(symbol: String, text: String) { self.symbol = symbol; self.text = text }
}

public enum StatusFormatter {
    public static let mrSymbol = "arrow.triangle.merge"
    public static let readySymbol = "checkmark.seal"
    public static let backlogSymbol = "tray.full"
    public static let inProgressSymbol = "bolt"

    static let errorText = "—"
    static let loadingText = "…"

    static func text(_ value: String?, hasError: Bool) -> String {
        if let value { return value }

        return hasError ? errorText : loadingText
    }

    public static func segments(gitlab: SourceResult<GitLabCounts>, jira: SourceResult<JiraCounts>) -> [TitleSegment] {
        let glError = gitlab.error != nil
        let jiraError = jira.error != nil
        return [
            TitleSegment(symbol: mrSymbol, text: text(gitlab.value.map { String($0.open) }, hasError: glError)),
            TitleSegment(symbol: readySymbol, text: text(gitlab.value.map { String($0.ready) }, hasError: glError)),
            TitleSegment(symbol: backlogSymbol, text: text(jira.value.map { String($0.backlog) }, hasError: jiraError)),
            TitleSegment(symbol: inProgressSymbol, text: text(jira.value.map { String($0.inProgress) }, hasError: jiraError)),
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
        } else if let e = gitlab.error {
            parts.append("GitLab błąd: \(e)")
        }

        if let j = jira.value {
            parts.append("Jira: \(j.backlog) backlog, \(j.inProgress) w toku")
        } else if let e = jira.error {
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
