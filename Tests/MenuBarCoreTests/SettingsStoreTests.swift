import XCTest
@testable import MenuBarCore

private struct StubImporter: CredentialImporting {
    var gitlab: Result<String, Error>
    var jira: Result<String, Error>
    func importedGitLabToken() throws -> String { try gitlab.get() }
    func importedJiraToken() throws -> String { try jira.get() }
}

private enum StubError: Error { case missing }

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

    func testSeedFromFilesPopulatesEmptyTokensOnce() {
        let secrets = InMemorySecretStore()
        let defaults = freshDefaults(#function)
        let store = SettingsStore(secrets: secrets, defaults: defaults)
        let importer = StubImporter(gitlab: .success("GT"), jira: .success("JT"))

        XCTAssertTrue(store.seedFromFilesIfNeeded(importer: importer))
        XCTAssertEqual(store.config.gitlabToken, "GT")
        XCTAssertEqual(store.config.jiraToken, "JT")

        // second call is a no-op (flag set)
        let importer2 = StubImporter(gitlab: .success("OTHER"), jira: .success("OTHER"))
        XCTAssertFalse(store.seedFromFilesIfNeeded(importer: importer2))
        XCTAssertEqual(store.config.gitlabToken, "GT")
    }

    func testSeedSkipsMissingFilesGracefully() {
        let store = SettingsStore(secrets: InMemorySecretStore(), defaults: freshDefaults(#function))
        let importer = StubImporter(gitlab: .failure(StubError.missing), jira: .failure(StubError.missing))
        XCTAssertFalse(store.seedFromFilesIfNeeded(importer: importer))
        XCTAssertEqual(store.config.gitlabToken, "")
    }

    func testSeedDoesNotReseedAfterFirstAttemptEvenWhenFilesAppear() {
        let secrets = InMemorySecretStore()
        let defaults = freshDefaults(#function)
        let store = SettingsStore(secrets: secrets, defaults: defaults)

        let missing = StubImporter(gitlab: .failure(StubError.missing), jira: .failure(StubError.missing))
        XCTAssertFalse(store.seedFromFilesIfNeeded(importer: missing))

        let present = StubImporter(gitlab: .success("GT"), jira: .success("JT"))
        let reopened = SettingsStore(secrets: secrets, defaults: defaults)
        XCTAssertFalse(reopened.seedFromFilesIfNeeded(importer: present))
        XCTAssertEqual(reopened.config.gitlabToken, "")
        XCTAssertEqual(reopened.config.jiraToken, "")
    }

    func testSeedFillsOnlyEmptyTokens() throws {
        let secrets = InMemorySecretStore()
        let store = SettingsStore(secrets: secrets, defaults: freshDefaults(#function))
        try store.save(AppConfig(gitlabHost: "gl", gitlabToken: "EXISTING", jiraHost: "jr", jiraToken: ""))

        let importer = StubImporter(gitlab: .success("FROM_FILE"), jira: .success("JT"))
        XCTAssertTrue(store.seedFromFilesIfNeeded(importer: importer))
        XCTAssertEqual(store.config.gitlabToken, "EXISTING")
        XCTAssertEqual(store.config.jiraToken, "JT")
    }
}
