import Foundation

@MainActor
public final class SettingsStore {
    private enum Key {
        static let gitlabHost = "gitlabHost"
        static let gitlabToken = "gitlabToken"
        static let jiraHost = "jiraHost"
        static let jiraToken = "jiraToken"
    }
    private static let seededFlag = "hasSeededFromFiles"

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
            jiraToken: secrets.string(forKey: Key.jiraToken) ?? ""
        )
    }

    public func save(_ newConfig: AppConfig) throws {
        try secrets.set(newConfig.gitlabHost, forKey: Key.gitlabHost)
        try secrets.set(newConfig.gitlabToken, forKey: Key.gitlabToken)
        try secrets.set(newConfig.jiraHost, forKey: Key.jiraHost)
        try secrets.set(newConfig.jiraToken, forKey: Key.jiraToken)
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
