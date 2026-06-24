import Foundation

@MainActor
public final class SettingsStore {
    private enum Key {
        static let gitlabHost = "gitlabHost"
        static let gitlabToken = "gitlabToken"
        static let jiraHost = "jiraHost"
        static let jiraToken = "jiraToken"
        static let githubHost = "githubHost"
        static let githubToken = "githubToken"
    }
    private enum Flag {
        static let gitlabEnabled = "gitlabEnabled"
        static let githubEnabled = "githubEnabled"
    }
    private static let seededFlag = "hasSeededFromFiles"

    private static func loadBool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private let secrets: SecretStore
    private let defaults: UserDefaults

    public private(set) var config: AppConfig

    public init(secrets: SecretStore, defaults: UserDefaults = .standard) {
        self.secrets = secrets
        self.defaults = defaults
        self.config = AppConfig(
            gitlabHost: secrets.string(forKey: Key.gitlabHost) ?? AppConfig.defaultGitLabHost,
            gitlabToken: secrets.string(forKey: Key.gitlabToken) ?? "",
            jiraHost: secrets.string(forKey: Key.jiraHost) ?? AppConfig.defaultJiraHost,
            jiraToken: secrets.string(forKey: Key.jiraToken) ?? "",
            githubHost: secrets.string(forKey: Key.githubHost) ?? AppConfig.defaultGitHubHost,
            githubToken: secrets.string(forKey: Key.githubToken) ?? "",
            gitlabEnabled: Self.loadBool(defaults, Flag.gitlabEnabled, default: true),
            githubEnabled: Self.loadBool(defaults, Flag.githubEnabled, default: true)
        )
    }

    public func save(_ newConfig: AppConfig) throws {
        try secrets.set(newConfig.gitlabHost, forKey: Key.gitlabHost)
        try secrets.set(newConfig.gitlabToken, forKey: Key.gitlabToken)
        try secrets.set(newConfig.jiraHost, forKey: Key.jiraHost)
        try secrets.set(newConfig.jiraToken, forKey: Key.jiraToken)
        try secrets.set(newConfig.githubHost, forKey: Key.githubHost)
        try secrets.set(newConfig.githubToken, forKey: Key.githubToken)
        defaults.set(newConfig.gitlabEnabled, forKey: Flag.gitlabEnabled)
        defaults.set(newConfig.githubEnabled, forKey: Flag.githubEnabled)
        config = newConfig
    }

    @discardableResult
    public func seedFromFilesIfNeeded(importer: CredentialImporting = Credentials()) -> Bool {
        guard !defaults.bool(forKey: Self.seededFlag) else { return false }
        defaults.set(true, forKey: Self.seededFlag)

        var updated = config
        var changed = false

        if updated.gitlabToken.isEmpty, let token = try? importer.importedGitLabToken() {
            updated.gitlabToken = token
            changed = true
        }

        if updated.jiraToken.isEmpty, let token = try? importer.importedJiraToken() {
            updated.jiraToken = token
            changed = true
        }

        if changed { try? save(updated) }

        return changed
    }
}
