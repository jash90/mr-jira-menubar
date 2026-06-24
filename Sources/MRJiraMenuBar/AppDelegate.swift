import AppKit
import MenuBarCore

private struct FailingGitLab: GitLabFetching {
    let error: Error
    func fetchOpenMRCount() async throws -> Int { throw error }
    func fetchReadyToMergeCount() async throws -> Int { throw error }
}

private struct FailingJira: JiraFetching {
    let error: Error
    func backlogCount() async throws -> Int { throw error }
    func inProgressCount() async throws -> Int { throw error }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: StatusStore?
    private let controller = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let creds = Credentials()

        let gitlab: GitLabFetching
        do {
            gitlab = GitLabClient(host: "drm-gitlab.redlabs.pl", token: try creds.gitlabToken())
        } catch {
            gitlab = FailingGitLab(error: error)
        }

        let jira: JiraFetching
        do {
            jira = JiraClient(host: "jira.redge.com", token: try creds.jiraToken())
        } catch {
            jira = FailingJira(error: error)
        }

        let store = StatusStore(gitlabClient: gitlab, jiraClient: jira)
        self.store = store

        controller.onRefresh = { [weak store] in store?.refreshNow() }
        store.onUpdate = { [weak self, weak store] in
            guard let self, let store else { return }
            self.controller.update(gitlab: store.gitlab, jira: store.jira, lastRefresh: store.lastRefresh)
        }
        store.start()
    }
}
