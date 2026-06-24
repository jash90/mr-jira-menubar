import Foundation

public struct AppConfig: Equatable, Sendable {
    public var gitlabHost: String
    public var gitlabToken: String
    public var jiraHost: String
    public var jiraToken: String
    public var githubHost: String
    public var githubToken: String
    public var gitlabEnabled: Bool
    public var githubEnabled: Bool

    public static let defaultGitLabHost = ""
    public static let defaultJiraHost = ""
    public static let defaultGitHubHost = "api.github.com"

    public init(
        gitlabHost: String = defaultGitLabHost,
        gitlabToken: String = "",
        jiraHost: String = defaultJiraHost,
        jiraToken: String = "",
        githubHost: String = defaultGitHubHost,
        githubToken: String = "",
        gitlabEnabled: Bool = true,
        githubEnabled: Bool = true
    ) {
        self.gitlabHost = gitlabHost
        self.gitlabToken = gitlabToken
        self.jiraHost = jiraHost
        self.jiraToken = jiraToken
        self.githubHost = githubHost
        self.githubToken = githubToken
        self.gitlabEnabled = gitlabEnabled
        self.githubEnabled = githubEnabled
    }

    public var gitlabActive: Bool { gitlabEnabled && !gitlabHost.isEmpty && !gitlabToken.isEmpty }
    public var jiraActive: Bool { !jiraHost.isEmpty && !jiraToken.isEmpty }
    public var githubActive: Bool { githubEnabled && !githubHost.isEmpty && !githubToken.isEmpty }
    public var hasAnySource: Bool { gitlabActive || jiraActive || githubActive }

    public var isComplete: Bool {
        !gitlabHost.isEmpty && !gitlabToken.isEmpty && !jiraHost.isEmpty && !jiraToken.isEmpty
    }
}
