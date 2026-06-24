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

private enum AppError: Error, CustomStringConvertible {
    case notConfigured
    var description: String { "Brak konfiguracji" }
}

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
        settings.seedFromFilesIfNeeded()

        store = StatusStore(
            gitlabClient: FailingGitLab(error: AppError.notConfigured),
            jiraClient: FailingJira(error: AppError.notConfigured)
        )
        store.onUpdate = { [weak self] in
            guard let self else { return }
            self.controller.update(
                gitlab: self.store.gitlab,
                github: self.store.github,
                jira: self.store.jira,
                lastRefresh: self.store.lastRefresh,
                visibility: self.visibility
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
        controller.githubHost = config.githubHost
        controller.githubWebHost = config.githubHost == "api.github.com" ? "github.com" : config.githubHost

        guard config.hasAnySource else {
            store.stop()
            store.setClients(
                gitlabClient: FailingGitLab(error: AppError.notConfigured),
                jiraClient: FailingJira(error: AppError.notConfigured),
                githubClient: nil
            )
            controller.showNeedsConfig()
            openSettings()
            return
        }

        let (gitlab, jira) = ClientFactory.make(config)
        store.setClients(gitlabClient: gitlab, jiraClient: jira, githubClient: ClientFactory.makeGitHub(config))
        controller.markConfigured()
        store.scheduleTimer()
        store.restartRefresh()
    }

    private func openSettings() {
        settingsWindow.show(config: settings.config)
    }
}
