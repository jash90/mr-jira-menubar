import Foundation

public enum ClientFactory {
    public static func make(_ config: AppConfig) -> (any GitLabFetching, any JiraFetching) {
        (
            GitLabClient(host: config.gitlabHost, token: config.gitlabToken),
            JiraClient(host: config.jiraHost, token: config.jiraToken)
        )
    }
}
