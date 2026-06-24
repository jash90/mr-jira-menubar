import Foundation

public enum ClientFactory {
    public static func make(_ config: AppConfig) -> (any GitLabFetching, any JiraFetching) {
        (
            GitLabClient(host: config.gitlabHost, token: config.gitlabToken),
            JiraClient(host: config.jiraHost, token: config.jiraToken)
        )
    }

    public static func makeGitHub(_ config: AppConfig) -> (any GitHubFetching)? {
        guard config.githubActive else { return nil }

        return GitHubClient(host: config.githubHost, token: config.githubToken)
    }
}
