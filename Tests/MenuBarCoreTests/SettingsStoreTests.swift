import XCTest
@testable import MenuBarCore

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaultsWhenEmpty() {
        let store = SettingsStore(secrets: InMemorySecretStore(), defaults: freshDefaults(#function))
        XCTAssertEqual(store.config.gitlabHost, AppConfig.defaultGitLabHost)
        XCTAssertEqual(store.config.jiraHost, AppConfig.defaultJiraHost)
        XCTAssertEqual(store.config.gitlabToken, "")
        XCTAssertFalse(store.config.isComplete)
    }

    func testSavePersistsToSecretStore() throws {
        let secrets = InMemorySecretStore()
        let store = SettingsStore(secrets: secrets, defaults: freshDefaults(#function))
        try store.save(AppConfig(gitlabHost: "gl", gitlabToken: "gt", jiraHost: "jr", jiraToken: "jt"))
        let reloaded = SettingsStore(secrets: secrets, defaults: freshDefaults(#function + "2"))
        XCTAssertEqual(reloaded.config, AppConfig(gitlabHost: "gl", gitlabToken: "gt", jiraHost: "jr", jiraToken: "jt"))
        XCTAssertTrue(reloaded.config.isComplete)
    }

    func testGitHubFieldsRoundTripAndDefaults() throws {
        let secrets = InMemorySecretStore()
        let store = SettingsStore(secrets: secrets, defaults: freshDefaults(#function))
        XCTAssertEqual(store.config.githubHost, AppConfig.defaultGitHubHost)
        XCTAssertEqual(store.config.githubToken, "")
        XCTAssertFalse(store.config.githubActive)

        var c = store.config
        c.githubToken = "ght"
        try store.save(c)

        let reloaded = SettingsStore(secrets: secrets, defaults: freshDefaults(#function + "2"))
        XCTAssertEqual(reloaded.config.githubToken, "ght")
        XCTAssertTrue(reloaded.config.githubActive)
    }

    func testHasAnySourceReflectsActiveSources() {
        let store = SettingsStore(secrets: InMemorySecretStore(), defaults: freshDefaults(#function))
        XCTAssertFalse(store.config.hasAnySource) // empty tokens
        var c = store.config
        c.jiraHost = "jira.example.com"
        c.jiraToken = "jt"
        XCTAssertTrue(c.jiraActive)
        XCTAssertTrue(c.hasAnySource)
        XCTAssertFalse(c.gitlabActive)
    }

    func testDisabledSourceIsNotActiveEvenWithToken() {
        var c = AppConfig(gitlabHost: "gl", gitlabToken: "gt", githubHost: "api.github.com", githubToken: "ght")
        XCTAssertTrue(c.gitlabActive)
        XCTAssertTrue(c.githubActive)
        c.gitlabEnabled = false
        c.githubEnabled = false
        XCTAssertFalse(c.gitlabActive)
        XCTAssertFalse(c.githubActive)
    }

    func testSecretsStoredEncryptedUnderSingleItem() throws {
        let secrets = InMemorySecretStore()
        let store = SettingsStore(secrets: secrets, defaults: freshDefaults(#function))
        try store.save(AppConfig(gitlabHost: "gl", gitlabToken: "SUPERSECRET", jiraHost: "jr", jiraToken: "jt"))

        XCTAssertNil(secrets.string(forKey: "gitlabToken"))
        XCTAssertNil(secrets.string(forKey: "jiraToken"))

        let blob = secrets.string(forKey: "credentials")
        XCTAssertNotNil(blob)
        XCTAssertFalse(blob!.contains("SUPERSECRET"))
        XCTAssertFalse(blob!.contains("gitlabToken"))

        let reloaded = SettingsStore(secrets: secrets, defaults: freshDefaults(#function + "2"))
        XCTAssertEqual(reloaded.config.gitlabToken, "SUPERSECRET")
        XCTAssertEqual(reloaded.config.jiraHost, "jr")
    }

    func testMigratesLegacyPlaintextItems() {
        let secrets = InMemorySecretStore([
            "gitlabHost": "gl", "gitlabToken": "gt", "jiraHost": "jr", "jiraToken": "jt",
        ])
        let store = SettingsStore(secrets: secrets, defaults: freshDefaults(#function))
        XCTAssertEqual(store.config.gitlabToken, "gt")
        XCTAssertTrue(store.config.jiraActive)

        // init auto-consolidates: legacy plaintext gone, single encrypted blob written.
        XCTAssertNil(secrets.string(forKey: "gitlabToken"))
        let blob = secrets.string(forKey: "credentials")
        XCTAssertNotNil(blob)
        XCTAssertFalse(blob!.contains("gt"))
    }

    func testEnabledCountersDefaultAllAndPersist() throws {
        let secrets = InMemorySecretStore()
        let defaults = freshDefaults(#function)
        let store = SettingsStore(secrets: secrets, defaults: defaults)
        XCTAssertEqual(store.config.enabledCounters, Set(StatusCounter.allCases))

        var c = store.config
        c.enabledCounters = [.gitlabOpen, .jiraBacklog]
        try store.save(c)

        let reloaded = SettingsStore(secrets: secrets, defaults: defaults)
        XCTAssertEqual(reloaded.config.enabledCounters, [.gitlabOpen, .jiraBacklog])
    }

    func testEnabledFlagsDefaultTrueAndPersist() throws {
        let secrets = InMemorySecretStore()
        let defaults = freshDefaults(#function)
        let store = SettingsStore(secrets: secrets, defaults: defaults)
        XCTAssertTrue(store.config.gitlabEnabled)
        XCTAssertTrue(store.config.githubEnabled)

        var c = store.config
        c.gitlabEnabled = false
        try store.save(c)

        let reloaded = SettingsStore(secrets: secrets, defaults: defaults)
        XCTAssertFalse(reloaded.config.gitlabEnabled)
        XCTAssertTrue(reloaded.config.githubEnabled)
    }
}
