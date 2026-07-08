import AppKit
import MenuBarCore

enum AppInfo {
    /// Bundle version when running as a packaged .app; a dev fallback matching
    /// scripts/build-app.sh's VERSION when launched via `swift run` (no Info.plist).
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.2.0"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let updateCheckInterval: TimeInterval = 6 * 60 * 60

    private let settings = SettingsStore(secrets: KeychainSecretStore())
    private let controller = StatusItemController()
    private let settingsWindow = SettingsWindowController()
    private var store: StatusStore!
    private var updateChecker: UpdateChecker!
    private var updateTimer: Timer?

    private var visibility: SourceVisibility {
        let c = settings.config
        return SourceVisibility(gitlab: c.gitlabActive, github: c.githubActive, jira: c.jiraActive)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = StatusStore()
        store.onUpdate = { [weak self] in self?.renderStatus() }

        updateChecker = UpdateChecker(client: GitHubReleaseClient(), currentVersion: AppInfo.version)
        updateChecker.onUpdate = { [weak self] in self?.renderStatus() }

        controller.onRefresh = { [weak self] in self?.store.refreshNow() }
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        controller.onDownloadUpdate = { [weak self] in self?.downloadAndOpenUpdate($0) }
        settingsWindow.onSave = { [weak self] newConfig in
            guard let self else { return }

            try self.settings.save(newConfig)
            self.applyConfig()
        }

        applyConfig()
        scheduleUpdateChecks()
    }

    private func renderStatus() {
        controller.update(
            gitlab: store.gitlab,
            github: store.github,
            jira: store.jira,
            lastRefresh: store.lastRefresh,
            visibility: visibility,
            enabledCounters: settings.config.enabledCounters,
            update: updateChecker.availableUpdate
        )
    }

    private func scheduleUpdateChecks() {
        Task { await updateChecker.check() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: Self.updateCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.updateChecker.check() }
        }
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

    private func downloadAndOpenUpdate(_ release: ReleaseInfo) {
        guard let source = release.dmgURL else {
            if let page = release.htmlURL { NSWorkspace.shared.open(page) }
            return
        }

        Task {
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: source)
                let downloads = try FileManager.default.url(
                    for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let destination = downloads.appendingPathComponent(source.lastPathComponent)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: tempURL, to: destination)
                NSWorkspace.shared.open(destination)
            } catch {
                self.presentDownloadError(error, fallback: release.htmlURL)
            }
        }
    }

    private func presentDownloadError(_ error: Error, fallback: URL?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Nie udało się pobrać aktualizacji"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Otwórz stronę release")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn, let fallback {
            NSWorkspace.shared.open(fallback)
        }
    }

    private func openSettings() {
        settingsWindow.show(config: settings.config)
    }
}
