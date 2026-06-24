# MR/Jira Menu Bar — Settings & Keychain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Move GitLab/Jira credentials (and hosts) out of fixed files into an in-app **Settings window**, persisted in the macOS **Keychain**, with a one-time first-launch import from the existing glab/jira files.

**Architecture:** Add a `SecretStore` abstraction (Keychain-backed at runtime, in-memory for tests) and a `SettingsStore` holding the editable `AppConfig` (GitLab host+token, Jira host+token). `StatusStore` gains runtime-swappable clients. The AppKit executable gets a SwiftUI Settings window and a "Ustawienia…" menu item; `AppDelegate` builds clients from the stored config and reconfigures on save.

**Tech Stack:** Swift 5.9, SwiftPM, AppKit + SwiftUI (NSHostingController), Security framework (Keychain), XCTest.

## Global Constraints

- macOS 13+, no third-party dependencies.
- `MenuBarCore` may import `Foundation` and `Security` (Keychain) but **NOT AppKit**. SwiftUI/AppKit stay in the executable target.
- Keychain service id: `com.redge.mrjiramenubar`. One generic-password item per field (account = field key).
- Editable fields: `gitlabHost`, `gitlabToken`, `jiraHost`, `jiraToken`. Approval threshold (2) and interval (300 s) stay hardcoded.
- Host defaults: `drm-gitlab.redlabs.pl`, `jira.redge.com`.
- First-launch import is one-time, guarded by `hasSeededFromFiles` in `UserDefaults`.
- Do not break existing passing tests or the public interfaces other code depends on.

## File Structure

```
Sources/MenuBarCore/
  SecretStore.swift     # NEW: SecretStore protocol, KeychainSecretStore, InMemorySecretStore
  AppConfig.swift       # NEW: AppConfig struct + CredentialImporting protocol
  SettingsStore.swift   # NEW: load/save AppConfig via SecretStore + one-time seeding
  ClientFactory.swift   # NEW: build (GitLabFetching, JiraFetching) from AppConfig
  Credentials.swift     # MODIFY: conform to CredentialImporting
  StatusStore.swift     # MODIFY: clients become swappable (setClients)
Sources/MRJiraMenuBar/
  SettingsView.swift          # NEW: SwiftUI form (hosts + tokens)
  SettingsWindowController.swift # NEW: hosts SettingsView in an NSWindow
  StatusItemController.swift  # MODIFY: settings menu item, needs-config state, host-aware links
  AppDelegate.swift           # MODIFY: SettingsStore + reconfigure-on-save wiring
Tests/MenuBarCoreTests/
  SecretStoreTests.swift   # NEW
  SettingsStoreTests.swift # NEW
  StatusStoreTests.swift   # MODIFY: add setClients test
```

---

### Task S1: SecretStore + Keychain + in-memory

**Files:**
- Create: `Sources/MenuBarCore/SecretStore.swift`
- Test: `Tests/MenuBarCoreTests/SecretStoreTests.swift`

**Interfaces:**
- Produces:
  - `protocol SecretStore: Sendable { func string(forKey: String) -> String?; func set(_ value: String?, forKey: String) throws }`
  - `final class KeychainSecretStore: SecretStore` (`init(service: String = "com.redge.mrjiramenubar")`)
  - `final class InMemorySecretStore: SecretStore` (`init(_ initial: [String: String] = [:])`)
  - `enum KeychainError: Error, CustomStringConvertible { case unexpectedStatus(OSStatus) }`

- [ ] **Step 1: Write the failing test** (Keychain itself is environment-dependent, so unit-test the in-memory store)

`Tests/MenuBarCoreTests/SecretStoreTests.swift`:

```swift
import XCTest
@testable import MenuBarCore

final class SecretStoreTests: XCTestCase {
    func testInMemoryRoundTrips() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(store.string(forKey: "k"))
        try store.set("secret", forKey: "k")
        XCTAssertEqual(store.string(forKey: "k"), "secret")
    }

    func testInMemorySetNilRemoves() throws {
        let store = InMemorySecretStore(["k": "v"])
        try store.set(nil, forKey: "k")
        XCTAssertNil(store.string(forKey: "k"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SecretStoreTests`
Expected: FAIL — `SecretStore`/`InMemorySecretStore` undefined.

- [ ] **Step 3: Write the implementation**

`Sources/MenuBarCore/SecretStore.swift`:

```swift
import Foundation
import Security

public protocol SecretStore: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String) throws
}

public enum KeychainError: Error, CustomStringConvertible {
    case unexpectedStatus(OSStatus)
    public var description: String {
        switch self {
        case .unexpectedStatus(let s):
            let msg = SecCopyErrorMessageString(s, nil) as String? ?? "OSStatus \(s)"
            return "Błąd Keychain: \(msg)"
        }
    }
}

public final class KeychainSecretStore: SecretStore {
    private let service: String
    public init(service: String = "com.redge.mrjiramenubar") { self.service = service }

    public func string(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?, forKey key: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)

        guard let value, let data = value.data(using: .utf8) else { return }

        var add = base
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String]
    public init(_ initial: [String: String] = [:]) { storage = initial }

    public func string(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ value: String?, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SecretStoreTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarCore/SecretStore.swift Tests/MenuBarCoreTests/SecretStoreTests.swift
git commit -m "feat: SecretStore abstraction with Keychain + in-memory backends"
```

---

### Task S2: AppConfig + SettingsStore (load/save/seed)

**Files:**
- Create: `Sources/MenuBarCore/AppConfig.swift`
- Create: `Sources/MenuBarCore/SettingsStore.swift`
- Modify: `Sources/MenuBarCore/Credentials.swift` (conform to `CredentialImporting`)
- Test: `Tests/MenuBarCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `SecretStore`, `Credentials`.
- Produces:
  - `struct AppConfig: Equatable, Sendable { var gitlabHost; var gitlabToken; var jiraHost; var jiraToken; static let defaultGitLabHost/defaultJiraHost: String; var isComplete: Bool; init(...) }`
  - `protocol CredentialImporting { func importedGitLabToken() throws -> String; func importedJiraToken() throws -> String }` (Credentials conforms)
  - `@MainActor final class SettingsStore { init(secrets: SecretStore, defaults: UserDefaults = .standard); var config: AppConfig (get); func save(_ config: AppConfig) throws; @discardableResult func seedFromFilesIfNeeded(importer: CredentialImporting = Credentials()) -> Bool }`

- [ ] **Step 1: Write the failing test**

`Tests/MenuBarCoreTests/SettingsStoreTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — `AppConfig`/`SettingsStore`/`CredentialImporting` undefined.

- [ ] **Step 3: Write `AppConfig.swift`**

```swift
import Foundation

public struct AppConfig: Equatable, Sendable {
    public var gitlabHost: String
    public var gitlabToken: String
    public var jiraHost: String
    public var jiraToken: String

    public static let defaultGitLabHost = "drm-gitlab.redlabs.pl"
    public static let defaultJiraHost = "jira.redge.com"

    public init(
        gitlabHost: String = defaultGitLabHost,
        gitlabToken: String = "",
        jiraHost: String = defaultJiraHost,
        jiraToken: String = ""
    ) {
        self.gitlabHost = gitlabHost
        self.gitlabToken = gitlabToken
        self.jiraHost = jiraHost
        self.jiraToken = jiraToken
    }

    public var isComplete: Bool {
        !gitlabHost.isEmpty && !gitlabToken.isEmpty && !jiraHost.isEmpty && !jiraToken.isEmpty
    }
}

public protocol CredentialImporting {
    func importedGitLabToken() throws -> String
    func importedJiraToken() throws -> String
}
```

- [ ] **Step 4: Conform `Credentials` to `CredentialImporting`**

Append to `Sources/MenuBarCore/Credentials.swift`:

```swift
extension Credentials: CredentialImporting {
    public func importedGitLabToken() throws -> String { try gitlabToken() }
    public func importedJiraToken() throws -> String { try jiraToken() }
}
```

- [ ] **Step 5: Write `SettingsStore.swift`**

```swift
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
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/MenuBarCore/AppConfig.swift Sources/MenuBarCore/SettingsStore.swift Sources/MenuBarCore/Credentials.swift Tests/MenuBarCoreTests/SettingsStoreTests.swift
git commit -m "feat: AppConfig + SettingsStore with Keychain persistence and one-time file seeding"
```

---

### Task S3: Swappable clients in StatusStore + ClientFactory

**Files:**
- Create: `Sources/MenuBarCore/ClientFactory.swift`
- Modify: `Sources/MenuBarCore/StatusStore.swift`
- Test: `Tests/MenuBarCoreTests/StatusStoreTests.swift`

**Interfaces:**
- Consumes: `AppConfig`, `GitLabFetching`, `JiraFetching`, `GitLabClient`, `JiraClient`.
- Produces:
  - `enum ClientFactory { static func make(_ config: AppConfig) -> (any GitLabFetching, any JiraFetching) }`
  - `StatusStore.setClients(gitlabClient: GitLabFetching, jiraClient: JiraFetching)` (existing `init`/`refresh`/`start` unchanged).

- [ ] **Step 1: Write the failing test**

Append to `Tests/MenuBarCoreTests/StatusStoreTests.swift` (inside the class; the `MutableGitLab`/`FakeJira` doubles already exist in that file):

```swift
    @MainActor
    func testSetClientsSwapsSourcesForNextRefresh() async {
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(1), ready: .success(0)),
            jiraClient: FakeJira(backlog: .success(0), inProgress: .success(0))
        )
        await store.refresh()
        XCTAssertEqual(store.gitlab.value, GitLabCounts(open: 1, ready: 0))

        store.setClients(
            gitlabClient: MutableGitLab(open: .success(9), ready: .success(4)),
            jiraClient: FakeJira(backlog: .success(2), inProgress: .success(1))
        )
        await store.refresh()
        XCTAssertEqual(store.gitlab.value, GitLabCounts(open: 9, ready: 4))
        XCTAssertEqual(store.jira.value, JiraCounts(backlog: 2, inProgress: 1))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter StatusStoreTests/testSetClientsSwapsSourcesForNextRefresh`
Expected: FAIL — `setClients` undefined.

- [ ] **Step 3: Modify `StatusStore.swift`**

Change the two client properties from `let` to `var`:

```swift
    private var gitlabClient: GitLabFetching
    private var jiraClient: JiraFetching
```

Add this method (e.g. right after `init`):

```swift
    public func setClients(gitlabClient: GitLabFetching, jiraClient: JiraFetching) {
        self.gitlabClient = gitlabClient
        self.jiraClient = jiraClient
    }
```

- [ ] **Step 4: Write `ClientFactory.swift`**

```swift
import Foundation

public enum ClientFactory {
    public static func make(_ config: AppConfig) -> (any GitLabFetching, any JiraFetching) {
        (
            GitLabClient(host: config.gitlabHost, token: config.gitlabToken),
            JiraClient(host: config.jiraHost, token: config.jiraToken)
        )
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter StatusStoreTests`
Expected: PASS (existing tests + the new one).

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarCore/ClientFactory.swift Sources/MenuBarCore/StatusStore.swift Tests/MenuBarCoreTests/StatusStoreTests.swift
git commit -m "feat: swappable StatusStore clients + ClientFactory from AppConfig"
```

---

### Task S4: Settings window + menu integration + AppDelegate rewire

**Files:**
- Create: `Sources/MRJiraMenuBar/SettingsView.swift`
- Create: `Sources/MRJiraMenuBar/SettingsWindowController.swift`
- Modify: `Sources/MRJiraMenuBar/StatusItemController.swift`
- Modify: `Sources/MRJiraMenuBar/AppDelegate.swift`

**Interfaces:**
- Consumes: `SettingsStore`, `AppConfig`, `ClientFactory`, `StatusStore`, `StatusFormatter`, `JiraClient`.
- Produces: a Settings window opened from the menu; clients rebuilt from stored config; host-aware links. No automated tests (AppKit/SwiftUI) — verified by build + manual run.

- [ ] **Step 1: Write `SettingsView.swift`**

```swift
import SwiftUI
import MenuBarCore

struct SettingsView: View {
    @State private var config: AppConfig
    private let onSave: (AppConfig) -> Void

    init(config: AppConfig, onSave: @escaping (AppConfig) -> Void) {
        _config = State(initialValue: config)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ustawienia").font(.headline)

            GroupBox("GitLab") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Host") { TextField("", text: $config.gitlabHost) }
                    LabeledContent("Token") { SecureField("PRIVATE-TOKEN", text: $config.gitlabToken) }
                }.padding(6)
            }

            GroupBox("Jira") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Host") { TextField("", text: $config.jiraHost) }
                    LabeledContent("Token") { SecureField("Bearer PAT", text: $config.jiraToken) }
                }.padding(6)
            }

            HStack {
                Spacer()
                Button("Zapisz") { onSave(config) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!config.isComplete)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
```

- [ ] **Step 2: Write `SettingsWindowController.swift`**

```swift
import AppKit
import SwiftUI
import MenuBarCore

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    var onSave: ((AppConfig) -> Void)?

    func show(config: AppConfig) {
        let view = SettingsView(config: config) { [weak self] newConfig in
            self?.onSave?(newConfig)
            self?.window?.close()
        }
        let hosting = NSHostingController(rootView: view)

        let win = window ?? NSWindow(contentViewController: hosting)
        if window == nil {
            win.styleMask = [.titled, .closable]
            win.title = "MR Jira Menu Bar — Ustawienia"
            win.isReleasedWhenClosed = false
            window = win
        } else {
            win.contentViewController = hosting
        }

        NSApp.activate(ignoringOtherApps: true)
        win.center()
        win.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 3: Modify `StatusItemController.swift`**

(a) Add stored hosts + a settings callback near the top of the class (after `var onRefresh`):

```swift
    var onOpenSettings: (() -> Void)?
    var gitlabHost = AppConfig.defaultGitLabHost
    var jiraHost = AppConfig.defaultJiraHost
```

(b) Replace the hardcoded `mrDashboardURL` constant and the `jiraURL` helper with host-aware versions. Remove the `private let mrDashboardURL = ...` line and add computed/instance helpers:

```swift
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
```

Update the two Jira `link(...)` calls in `buildMenu` to use the instance method (drop the `Self.`):

```swift
        menu.addItem(link("  Backlog: \(backlogText)", url: jiraURL(JiraClient.backlogJQL)))
        menu.addItem(link("  W toku: \(progText)", url: jiraURL(JiraClient.inProgressJQL)))
```

Delete the old `static func jiraURL(_:) -> URL` method.

(c) Add a "Ustawienia…" item to `buildMenu` (insert just before the `quitItem` lines):

```swift
        let settingsItem = NSMenuItem(title: "Ustawienia…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
```

(d) Add a `showNeedsConfig()` method and the `openSettings` action (place near `showError`):

```swift
    func showNeedsConfig() {
        guard let button = statusItem.button else { return }
        let attachment = NSTextAttachment()
        attachment.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        button.attributedTitle = NSAttributedString(attachment: attachment)
        button.toolTip = "Skonfiguruj tokeny GitLab/Jira w Ustawieniach"

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

    @objc private func openSettings() { onOpenSettings?() }
```

Also add `import MenuBarCore` is already present. (AppConfig comes from MenuBarCore.)

- [ ] **Step 4: Rewrite `AppDelegate.swift`**

```swift
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
            try? self.settings.save(newConfig)
            self.applyConfig()
        }

        applyConfig()
        store.start()
    }

    private func applyConfig() {
        let config = settings.config
        controller.gitlabHost = config.gitlabHost
        controller.jiraHost = config.jiraHost

        guard config.isComplete else {
            controller.showNeedsConfig()
            openSettings()
            return
        }

        let (gitlab, jira) = ClientFactory.make(config)
        store.setClients(gitlabClient: gitlab, jiraClient: jira)
        store.refreshNow()
    }

    private func openSettings() {
        settingsWindow.show(config: settings.config)
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 6: Run the full test suite (ensure nothing regressed)**

Run: `swift test`
Expected: all tests pass (previous suite + S1–S3 additions).

- [ ] **Step 7: Manual verification**

Run: `swift run MRJiraMenuBar`
Expected:
- On a machine that already has the glab/jira files, first launch seeds them → menu bar shows the four counters as before.
- Open the menu → "Ustawienia…" (⌘,) opens a window with GitLab/Jira host + token fields (tokens masked). The window comes to the front and accepts typing.
- Change a token to something invalid → Save → that source shows the error symbol/row; the other keeps working. Restore it → Save → counters return.
- Quit and relaunch → values persist (read from Keychain), no re-seeding, no file reads required.
- With Keychain cleared (fresh) and no glab/jira files, the item shows the gear "needs configuration" state and opens Settings automatically.

- [ ] **Step 8: Commit**

```bash
git add Sources/MRJiraMenuBar
git commit -m "feat: in-app Settings window with Keychain-backed credentials"
```

---

## Self-Review

- Tokens-in-settings (not fixed files) → S2 (SettingsStore over SecretStore) + S4 (Settings UI). ✓
- Keychain storage → S1 (`KeychainSecretStore`). ✓
- Editable tokens **and hosts** → `AppConfig` (S2), host-aware links + client building (S3/S4). ✓
- One-time import from glab/jira files → `seedFromFilesIfNeeded` (S2), called in `AppDelegate` (S4). ✓
- Source independence preserved → `FailingGitLab`/`FailingJira` per source + `setClients` (S3/S4). ✓
- Threshold (2)/interval (300 s) stay hardcoded → unchanged in `GitLabClient`/`StatusStore`. ✓
- `MenuBarCore` AppKit-free (Security only) → S1 imports `Security`, not AppKit. ✓
- Type consistency: `SecretStore` (S1) consumed by `SettingsStore` (S2); `AppConfig` (S2) consumed by `ClientFactory`/`StatusItemController`/`AppDelegate` (S3/S4); `setClients` (S3) called in S4. ✓
