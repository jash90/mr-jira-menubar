# MR/Jira Menu Bar — Per-Source Enable Toggles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Give GitLab and GitHub an explicit enable/disable toggle in Settings, independent of whether a token is present. Disabling a source hides it and stops fetching, but keeps its token in the Keychain. (Jira has no toggle — it is active whenever it has a token.)

**Architecture:** Add `gitlabEnabled`/`githubEnabled` booleans to `AppConfig` (default `true`) and fold them into the existing `gitlabActive`/`githubActive` computeds. Everything downstream (visibility, fetching, needs-config) already keys off `*Active`, so no changes are needed there. Persist the two flags in `UserDefaults` (they are preferences, not secrets). The Settings UI gains a toggle per source.

**Tech Stack:** Swift 5.9, SwiftPM, AppKit + SwiftUI, Foundation/Security, XCTest.

## Global Constraints

- macOS 13+, no third-party deps. `MenuBarCore` imports only `Foundation`/`Security` (NOT AppKit).
- Toggles for **GitLab and GitHub only**. Jira stays active whenever host+token are set.
- Disabling a source: hidden + not fetched; **token is retained** in the Keychain.
- Enable flags persist in `UserDefaults` and **default to `true`** when absent (so existing installs are unchanged — GitLab stays on, GitHub stays on but still needs a token to show).
- `active = enabled && host&&token non-empty`. `hasAnySource` (and the needs-config gate) already derive from the `*Active` computeds — do not change that logic.
- Keep the existing 66 tests passing; add new `AppConfig`/`SettingsStore` params with defaults so existing call sites compile.

## File Structure

```
Sources/MenuBarCore/
  AppConfig.swift       # MODIFY: + gitlabEnabled/githubEnabled, fold into *Active
  SettingsStore.swift   # MODIFY: load/save the two flags in UserDefaults (default true)
Sources/MRJiraMenuBar/
  SettingsView.swift    # MODIFY: a "Włącz" toggle in the GitLab and GitHub GroupBoxes
Tests/MenuBarCoreTests/
  SettingsStoreTests.swift # MODIFY: enabled-folds-into-active + persistence/default-true
```

---

### Task T1: Enabled flags in AppConfig + SettingsStore persistence

**Files:**
- Modify: `Sources/MenuBarCore/AppConfig.swift`
- Modify: `Sources/MenuBarCore/SettingsStore.swift`
- Test: `Tests/MenuBarCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `AppConfig.gitlabEnabled`, `AppConfig.githubEnabled` (both `Bool`, default `true`); `gitlabActive`/`githubActive` now include the enabled flag. `SettingsStore` persists both flags in `UserDefaults`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/MenuBarCoreTests/SettingsStoreTests.swift` (inside the class):

```swift
    func testDisabledSourceIsNotActiveEvenWithToken() {
        var c = AppConfig(gitlabHost: "gl", gitlabToken: "gt", githubHost: "api.github.com", githubToken: "ght")
        XCTAssertTrue(c.gitlabActive)
        XCTAssertTrue(c.githubActive)
        c.gitlabEnabled = false
        c.githubEnabled = false
        XCTAssertFalse(c.gitlabActive)
        XCTAssertFalse(c.githubActive)
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — `gitlabEnabled`/`githubEnabled` undefined.

- [ ] **Step 3: Modify `AppConfig.swift`**

Add the two stored properties (after `githubToken`):

```swift
    public var gitlabEnabled: Bool
    public var githubEnabled: Bool
```

Add the two parameters to `init` (at the end, defaulted) and assign them:

```swift
        githubToken: String = "",
        gitlabEnabled: Bool = true,
        githubEnabled: Bool = true
    ) {
        self.gitlabHost = gitlabHost
        self.gitlabToken = gitlabToken
        self.jiraHost = jiraHost
        self.jiraToken = jiraToken
        self.githubHost = githubHost
        self.githubToken = githubToken
        self.gitlabEnabled = gitlabEnabled
        self.githubEnabled = githubEnabled
    }
```

Fold the flags into the two active computeds (Jira unchanged):

```swift
    public var gitlabActive: Bool { gitlabEnabled && !gitlabHost.isEmpty && !gitlabToken.isEmpty }
    public var jiraActive: Bool { !jiraHost.isEmpty && !jiraToken.isEmpty }
    public var githubActive: Bool { githubEnabled && !githubHost.isEmpty && !githubToken.isEmpty }
```

(`hasAnySource` and `isComplete` stay as they are.)

- [ ] **Step 4: Modify `SettingsStore.swift`**

Add UserDefaults keys for the flags (below the `Key` enum):

```swift
    private enum Flag {
        static let gitlabEnabled = "gitlabEnabled"
        static let githubEnabled = "githubEnabled"
    }
```

Add a default-true loader helper (inside the class):

```swift
    private static func loadBool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
```

Extend the `config` assignment in `init` to load the flags:

```swift
            githubToken: secrets.string(forKey: Key.githubToken) ?? "",
            gitlabEnabled: Self.loadBool(defaults, Flag.gitlabEnabled, default: true),
            githubEnabled: Self.loadBool(defaults, Flag.githubEnabled, default: true)
        )
```

Persist the flags in `save(_:)` (after the secret writes, before `config = newConfig`):

```swift
        defaults.set(newConfig.gitlabEnabled, forKey: Flag.gitlabEnabled)
        defaults.set(newConfig.githubEnabled, forKey: Flag.githubEnabled)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS (all existing + 2 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarCore/AppConfig.swift Sources/MenuBarCore/SettingsStore.swift Tests/MenuBarCoreTests/SettingsStoreTests.swift
git commit -m "feat: per-source enable flags for GitLab/GitHub folded into active state"
```

---

### Task T2: Enable toggles in the Settings UI

**Files:**
- Modify: `Sources/MRJiraMenuBar/SettingsView.swift`

**Interfaces:**
- Consumes: `AppConfig.gitlabEnabled`/`githubEnabled`. No automated test (SwiftUI) — build + manual.

- [ ] **Step 1: Modify `SettingsView.swift`**

Replace the GitLab `GroupBox` with a version that has a toggle and disables its fields when off:

```swift
            GroupBox("GitLab") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Włącz GitLab", isOn: $config.gitlabEnabled)
                    LabeledContent("Host") { TextField("", text: $config.gitlabHost) }
                    LabeledContent("Token") { SecureField("PRIVATE-TOKEN", text: $config.gitlabToken) }
                        .disabled(!config.gitlabEnabled)
                }.padding(6)
            }
```

Replace the GitHub `GroupBox` likewise:

```swift
            GroupBox("GitHub") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Włącz GitHub", isOn: $config.githubEnabled)
                    LabeledContent("Host") { TextField("api.github.com", text: $config.githubHost) }
                    LabeledContent("Token") { SecureField("Personal Access Token", text: $config.githubToken) }
                        .disabled(!config.githubEnabled)
                }.padding(6)
            }
```

(Leave the Jira GroupBox and the Save button — already gated on `!config.hasAnySource` — unchanged.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!` no errors.

- [ ] **Step 3: Run the full test suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 4: Manual verification**

Run: `swift run MRJiraMenuBar`
Expected:
- Settings shows a "Włącz GitLab" and "Włącz GitHub" toggle.
- Turn GitLab off → its host/token fields grey out; after Save, the GitLab segments disappear from the menu bar and GitLab is no longer fetched; GitLab's token remains saved (turn it back on → segments return without re-typing).
- GitHub behaves the same; Jira has no toggle.
- Disabling every source with a token (so nothing is active) shows the needs-config gear.

- [ ] **Step 5: Commit**

```bash
git add Sources/MRJiraMenuBar/SettingsView.swift
git commit -m "feat: GitLab/GitHub enable toggles in Settings"
```

---

## Self-Review

- Explicit enable/disable per source (GitLab, GitHub) → T1 flags + T2 toggles. ✓
- Jira has no toggle → `jiraActive` unchanged. ✓
- Disable hides + stops fetching, keeps token → flags fold into `*Active` (drives visibility + `makeGitLab`/`makeGitHub` nil), tokens stay in Keychain (only the flag changes). ✓
- Default true / no behavior change for existing installs → `loadBool(..., default: true)`. ✓
- No regressions → new params defaulted; `hasAnySource`/needs-config logic untouched; existing 66 tests compile/pass. ✓
