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

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.seedFromFilesIfNeeded()

        store = StatusStore(
            gitlabClient: FailingGitLab(error: AppError.notConfigured),
            jiraClient: FailingJira(error: AppError.notConfigured)
        )
        store.onUpdate = { [weak self] in
            guard let self else { return }
            self.controller.update(gitlab: self.store.gitlab, jira: self.store.jira, lastRefresh: self.store.lastRefresh)
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

        guard config.isComplete else {
            store.stop()
            store.setClients(
                gitlabClient: FailingGitLab(error: AppError.notConfigured),
                jiraClient: FailingJira(error: AppError.notConfigured)
            )
            controller.showNeedsConfig()
            openSettings()
            return
        }

        let (gitlab, jira) = ClientFactory.make(config)
        store.setClients(gitlabClient: gitlab, jiraClient: jira)
        controller.markConfigured()
        store.scheduleTimer()
        store.restartRefresh()
    }

    private func openSettings() {
        settingsWindow.show(config: settings.config)
    }
}
