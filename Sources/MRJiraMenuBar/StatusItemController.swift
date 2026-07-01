import AppKit
import MenuBarCore

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var gitlabHost = AppConfig.defaultGitLabHost { didSet { gitlabHost = normalizedHost(gitlabHost) } }
    var jiraHost = AppConfig.defaultJiraHost { didSet { jiraHost = normalizedHost(jiraHost) } }
    var githubWebHost = "github.com" { didSet { githubWebHost = normalizedHost(githubWebHost) } }
    private var isNeedsConfig = false

    private var mrDashboardURL: URL {
        URL(string: "https://\(gitlabHost)/dashboard/merge_requests?scope=created_by_me&state=opened")!
    }

    private func jiraURL(_ jql: String) -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = jiraHost
        comps.path = "/issues/"
        comps.queryItems = [.init(name: "jql", value: jql)]
        return comps.url!
    }

    private var githubPRsURL: URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = githubWebHost
        comps.path = "/pulls"
        comps.queryItems = [.init(name: "q", value: "is:open is:pr author:@me")]
        return comps.url!
    }

    func markConfigured() {
        isNeedsConfig = false
    }

    func update(
        gitlab: SourceResult<GitLabCounts>,
        github: SourceResult<GitHubCounts>,
        jira: SourceResult<JiraCounts>,
        lastRefresh: Date?,
        visibility: SourceVisibility
    ) {
        guard !isNeedsConfig, let button = statusItem.button else { return }

        button.attributedTitle = Self.attributedTitle(
            StatusFormatter.segments(gitlab: gitlab, github: github, jira: jira, visibility: visibility))
        button.toolTip = StatusFormatter.tooltip(
            gitlab: gitlab, github: github, jira: jira, lastRefresh: lastRefresh, visibility: visibility)
        statusItem.menu = buildMenu(gitlab: gitlab, github: github, jira: jira, lastRefresh: lastRefresh, visibility: visibility)
    }

    func showError(_ message: String) {
        guard let button = statusItem.button else { return }
        let attachment = NSTextAttachment()
        attachment.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        button.attributedTitle = NSAttributedString(attachment: attachment)
        button.toolTip = message

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Błąd: \(message)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Odśwież teraz", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Zakończ", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    static func attributedTitle(_ segments: [TitleSegment]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        for (i, seg) in segments.enumerated() {
            if let image = NSImage(systemSymbolName: seg.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let attachment = NSTextAttachment()
                attachment.image = image
                result.append(NSAttributedString(attachment: attachment))
            }
            let trailing = (i < segments.count - 1) ? "  " : ""
            result.append(NSAttributedString(string: " \(seg.text)\(trailing)"))
        }
        return result
    }

    private func buildMenu(
        gitlab: SourceResult<GitLabCounts>,
        github: SourceResult<GitHubCounts>,
        jira: SourceResult<JiraCounts>,
        lastRefresh: Date?,
        visibility: SourceVisibility
    ) -> NSMenu {
        let menu = NSMenu()

        if visibility.gitlab {
            menu.addItem(header("GitLab — moje MR"))
            let openText = gitlab.value.map { String($0.open) } ?? (gitlab.error != nil ? "—" : "…")
            let readyText = gitlab.value.map { String($0.ready) } ?? (gitlab.error != nil ? "—" : "…")
            menu.addItem(link("  Otwarte: \(openText)", url: mrDashboardURL))
            menu.addItem(link("  Gotowe do mergu: \(readyText)", url: mrDashboardURL))
            if let e = gitlab.error { menu.addItem(NSMenuItem(title: "  Błąd: \(e)", action: nil, keyEquivalent: "")) }

            menu.addItem(.separator())
        }

        if visibility.github {
            menu.addItem(header("GitHub — moje PR"))
            let openText = github.value.map { String($0.open) } ?? (github.error != nil ? "—" : "…")
            let approvedText = github.value.map { String($0.approved) } ?? (github.error != nil ? "—" : "…")
            menu.addItem(link("  Otwarte: \(openText)", url: githubPRsURL))
            menu.addItem(link("  Approved: \(approvedText)", url: githubPRsURL))
            if let e = github.error { menu.addItem(NSMenuItem(title: "  Błąd: \(e)", action: nil, keyEquivalent: "")) }

            menu.addItem(.separator())
        }

        if visibility.jira {
            menu.addItem(header("Jira"))
            let backlogText = jira.value.map { String($0.backlog) } ?? (jira.error != nil ? "—" : "…")
            let progText = jira.value.map { String($0.inProgress) } ?? (jira.error != nil ? "—" : "…")
            menu.addItem(link("  Backlog: \(backlogText)", url: jiraURL(JiraClient.backlogJQL)))
            menu.addItem(link("  W toku: \(progText)", url: jiraURL(JiraClient.inProgressJQL)))
            if let e = jira.error { menu.addItem(NSMenuItem(title: "  Błąd: \(e)", action: nil, keyEquivalent: "")) }

            menu.addItem(.separator())
        }

        if let last = lastRefresh {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            menu.addItem(NSMenuItem(title: "Ostatnie odświeżenie: \(f.string(from: last))", action: nil, keyEquivalent: ""))
        }
        let refreshItem = NSMenuItem(title: "Odśwież teraz", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let settingsItem = NSMenuItem(title: "Ustawienia…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(title: "Zakończ", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func link(_ title: String, url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openLink(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        return item
    }

    func showNeedsConfig() {
        isNeedsConfig = true

        guard let button = statusItem.button else { return }

        let attachment = NSTextAttachment()
        attachment.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        button.attributedTitle = NSAttributedString(attachment: attachment)
        button.toolTip = "Skonfiguruj tokeny (GitLab / GitHub / Jira) w Ustawieniach"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Brak konfiguracji — uzupełnij tokeny", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Ustawienia…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(title: "Zakończ", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func refresh() { onRefresh?() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
