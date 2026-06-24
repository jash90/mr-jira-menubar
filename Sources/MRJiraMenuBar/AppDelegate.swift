import AppKit
import MenuBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: StatusStore?
    private let controller = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let creds = Credentials()
        do {
            let gitlab = GitLabClient(host: "drm-gitlab.redlabs.pl", token: try creds.gitlabToken())
            let jira = JiraClient(host: "jira.redge.com", token: try creds.jiraToken())
            let store = StatusStore(gitlabClient: gitlab, jiraClient: jira)
            self.store = store

            controller.onRefresh = { [weak store] in store?.refreshNow() }
            store.onUpdate = { [weak self, weak store] in
                guard let self, let store else { return }
                self.controller.update(gitlab: store.gitlab, jira: store.jira, lastRefresh: store.lastRefresh)
            }
            store.start()
        } catch {
            controller.showError(StatusStore.message(error))
        }
    }
}
