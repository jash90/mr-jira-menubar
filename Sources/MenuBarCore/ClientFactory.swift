import Foundation

public enum ClientFactory {
    public static func make(_ config: AppConfig) -> (any GitLabFetching, any JiraFetching) {
        (
            GitLabClient(host: config.gitlabHost, token: config.gitlabToken),
            JiraClient(host: config.jiraHost, token: config.jiraToken)
        )
    }

    public static func makeGitLab(_ config: AppConfig) -> (any GitLabFetching)? {
        guard config.gitlabActive else { return nil }

        return GitLabClient(host: config.gitlabHost, token: config.gitlabToken)
    }

    public static func makeJira(_ config: AppConfig) -> (any JiraFetching)? {
        guard config.jiraActive else { return nil }

        return JiraClient(host: config.jiraHost, token: config.jiraToken)
    }

    public static func makeGitHub(_ config: AppConfig) -> (any GitHubFetching)? {
        guard config.githubActive else { return nil }

        return GitHubClient(host: config.githubHost, token: config.githubToken)
    }
}
