import Foundation

@MainActor
public final class SettingsStore {
    private enum Key {
        static let credentials = "credentials"
        static let gitlabHost = "gitlabHost"
        static let gitlabToken = "gitlabToken"
        static let jiraHost = "jiraHost"
        static let jiraToken = "jiraToken"
        static let githubHost = "githubHost"
        static let githubToken = "githubToken"

        static let legacy = [gitlabHost, gitlabToken, jiraHost, jiraToken, githubHost, githubToken]
    }
    private enum Flag {
        static let gitlabEnabled = "gitlabEnabled"
        static let githubEnabled = "githubEnabled"
        static let enabledCounters = "enabledCounters"
    }
    private static func loadBool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
    private static func loadCounters(_ defaults: UserDefaults) -> Set<StatusCounter> {
        guard let raw = defaults.array(forKey: Flag.enabledCounters) as? [String] else {
            return Set(StatusCounter.allCases)
        }

        return Set(raw.compactMap(StatusCounter.init(rawValue:)))
    }

    /// Reads the single encrypted credentials blob, falling back to the pre-consolidation
    /// plaintext per-field items so existing installs migrate on the next save.
    private static func loadSecrets(_ secrets: SecretStore) -> [String: String] {
        if let blob = secrets.string(forKey: Key.credentials),
           let data = Data(base64Encoded: blob),
           let plain = try? SecretCrypto.open(data),
           let dict = try? JSONDecoder().decode([String: String].self, from: plain) {
            return dict
        }

        var legacy: [String: String] = [:]
        for key in Key.legacy {
            if let value = secrets.string(forKey: key) { legacy[key] = value }
        }
        return legacy
    }

    private let secrets: SecretStore
    private let defaults: UserDefaults

    public private(set) var config: AppConfig

    public init(secrets: SecretStore, defaults: UserDefaults = .standard) {
        self.secrets = secrets
        self.defaults = defaults

        let hadConsolidated = secrets.string(forKey: Key.credentials) != nil
        let stored = Self.loadSecrets(secrets)
        self.config = AppConfig(
            gitlabHost: stored[Key.gitlabHost] ?? AppConfig.defaultGitLabHost,
            gitlabToken: stored[Key.gitlabToken] ?? "",
            jiraHost: stored[Key.jiraHost] ?? AppConfig.defaultJiraHost,
            jiraToken: stored[Key.jiraToken] ?? "",
            githubHost: stored[Key.githubHost] ?? AppConfig.defaultGitHubHost,
            githubToken: stored[Key.githubToken] ?? "",
            gitlabEnabled: Self.loadBool(defaults, Flag.gitlabEnabled, default: true),
            githubEnabled: Self.loadBool(defaults, Flag.githubEnabled, default: true),
            enabledCounters: Self.loadCounters(defaults)
        )

        if !hadConsolidated, !stored.isEmpty {
            try? save(config)
        }
    }

    public func save(_ newConfig: AppConfig) throws {
        let secretsDict: [String: String] = [
            Key.gitlabHost: newConfig.gitlabHost,
            Key.gitlabToken: newConfig.gitlabToken,
            Key.jiraHost: newConfig.jiraHost,
            Key.jiraToken: newConfig.jiraToken,
            Key.githubHost: newConfig.githubHost,
            Key.githubToken: newConfig.githubToken,
        ]
        let sealed = try SecretCrypto.seal(JSONEncoder().encode(secretsDict))
        try secrets.set(sealed.base64EncodedString(), forKey: Key.credentials)

        for key in Key.legacy {
            try? secrets.set(nil, forKey: key)
        }

        defaults.set(newConfig.gitlabEnabled, forKey: Flag.gitlabEnabled)
        defaults.set(newConfig.githubEnabled, forKey: Flag.githubEnabled)
        defaults.set(newConfig.enabledCounters.map(\.rawValue), forKey: Flag.enabledCounters)
        config = newConfig
    }
}
