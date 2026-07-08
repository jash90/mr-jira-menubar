import AppKit
import MenuBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore(secrets: KeychainSecretStore())
    private let controller = StatusItemController()
    private let settingsWindow = SettingsWindowController()
    private var store: StatusStore!

    private var visibility: SourceVisibility {
        let c = settings.config
        return SourceVisibility(gitlab: c.gitlabActive, github: c.githubActive, jira: c.jiraActive)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = StatusStore()
        store.onUpdate = { [weak self] in
            guard let self else { return }
            self.controller.update(
                gitlab: self.store.gitlab,
                github: self.store.github,
                jira: self.store.jira,
                lastRefresh: self.store.lastRefresh,
                visibility: self.visibility,
                enabledCounters: self.settings.config.enabledCounters
            )
        }
        controller.onRefresh = { [weak self] in self?.store.refreshNow() }
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        settingsWindow.onSave = { [weak self] newConfig in
            guard let self else { return }

            try self.settings.save(newConfig)
            self.applyConfig()
        }

        applyConfig()
    }

    private func applyConfig() {
        let config = settings.config
        controller.gitlabHost = config.gitlabHost
        controller.jiraHost = config.jiraHost
        let githubAPIHost = GitHubClient.normalizeHost(config.githubHost)
        controller.githubWebHost = githubAPIHost == "api.github.com" ? "github.com" : githubAPIHost

        guard config.hasAnySource else {
            store.stop()
            store.setClients(gitlabClient: nil, jiraClient: nil, githubClient: nil)
            controller.showNeedsConfig()
            openSettings()
            return
        }

        store.setClients(
            gitlabClient: ClientFactory.makeGitLab(config),
            jiraClient: ClientFactory.makeJira(config),
            githubClient: ClientFactory.makeGitHub(config)
        )
        controller.markConfigured()
        store.scheduleTimer()
        store.restartRefresh()
    }

    private func openSettings() {
        settingsWindow.show(config: settings.config)
    }
}
