import Foundation

public struct AppConfig: Equatable, Sendable {
    public var gitlabHost: String
    public var gitlabToken: String
    public var jiraHost: String
    public var jiraToken: String
    public var githubHost: String
    public var githubToken: String

    public static let defaultGitLabHost = "drm-gitlab.redlabs.pl"
    public static let defaultJiraHost = "jira.redge.com"
    public static let defaultGitHubHost = "api.github.com"

    public init(
        gitlabHost: String = defaultGitLabHost,
        gitlabToken: String = "",
        jiraHost: String = defaultJiraHost,
        jiraToken: String = "",
        githubHost: String = defaultGitHubHost,
        githubToken: String = ""
    ) {
        self.gitlabHost = gitlabHost
        self.gitlabToken = gitlabToken
        self.jiraHost = jiraHost
        self.jiraToken = jiraToken
        self.githubHost = githubHost
        self.githubToken = githubToken
    }

    public var gitlabActive: Bool { !gitlabHost.isEmpty && !gitlabToken.isEmpty }
    public var jiraActive: Bool { !jiraHost.isEmpty && !jiraToken.isEmpty }
    public var githubActive: Bool { !githubHost.isEmpty && !githubToken.isEmpty }
    public var hasAnySource: Bool { gitlabActive || jiraActive || githubActive }

    public var isComplete: Bool {
        !gitlabHost.isEmpty && !gitlabToken.isEmpty && !jiraHost.isEmpty && !jiraToken.isEmpty
    }
}

public protocol CredentialImporting {
    func importedGitLabToken() throws -> String
    func importedJiraToken() throws -> String
}
