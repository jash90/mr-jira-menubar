# MR/Jira Menu Bar — GitHub Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add GitHub as a third source alongside GitLab and Jira: two new menu-bar counters — my open PRs and my approved PRs — configured (host + token) in Settings and stored in the Keychain like the others.

**Architecture:** A `GitHubClient` (GitHub Search API) mirrors the existing clients. `AppConfig`/`SettingsStore` gain GitHub host+token. `StatusStore` gains a third (optional) source. `StatusFormatter` becomes visibility-aware so only configured sources render. The AppKit UI adds a GitHub settings section, GitHub menu-bar segments, and a GitHub menu section. Per-source independence and the "needs config when nothing is set" behavior are preserved.

**Tech Stack:** Swift 5.9, SwiftPM, AppKit + SwiftUI, Foundation/Security, XCTest. No third-party deps.

## Global Constraints

- macOS 13+, no third-party deps. `MenuBarCore` imports only `Foundation`/`Security` (NOT AppKit).
- GitHub counters: **open PRs** = `is:pr is:open author:@me archived:false`; **approved** = same + `review:approved`. Counts via GitHub Search API `total_count`.
- GitHub host configurable, default `api.github.com`. For `api.github.com` the API path is `/search/issues`; for any other (Enterprise) host it is `/api/v3/search/issues`.
- Required GitHub headers: `Authorization: Bearer <token>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, and a non-empty `User-Agent` (GitHub rejects requests without one).
- No `gh` CLI on this machine → GitHub token is **not** seeded from files; it is entered in Settings. (GitLab/Jira seeding is unchanged.)
- Each source is independent: a source with empty host/token is **hidden** (no segment, not fetched), not shown as an error. "Needs config" only when NO source is active.
- **Backward compatibility:** add new parameters with defaults so existing call sites and tests keep compiling. Do not break the current 43 passing tests.
- Approval threshold (GitLab 2) and interval (300 s) stay hardcoded.

## File Structure

```
Sources/MenuBarCore/
  GitHubClient.swift    # NEW: GitHubFetching, GitHubClient, GitHubError
  AppConfig.swift       # MODIFY: + githubHost/githubToken, *Active computeds, hasAnySource
  SettingsStore.swift   # MODIFY: persist/load GitHub fields
  StatusStore.swift     # MODIFY: + GitHubCounts, github source, optional githubClient, refreshGitHub
  ClientFactory.swift   # MODIFY: + makeGitHub(_:)
  StatusFormatter.swift # MODIFY: + SourceVisibility, GitHub symbols, visibility-aware segments/tooltip
Sources/MRJiraMenuBar/
  SettingsView.swift          # MODIFY: + GitHub GroupBox, Save gated on hasAnySource
  StatusItemController.swift  # MODIFY: GitHub segments + menu section + host-aware PR link, visibility
  AppDelegate.swift           # MODIFY: build GitHub client, pass github+visibility, needs-config via hasAnySource
Tests/MenuBarCoreTests/
  GitHubClientTests.swift  # NEW
  SettingsStoreTests.swift # MODIFY: GitHub round-trip + active flags
  StatusStoreTests.swift   # MODIFY: GitHub fetch + inactive-clears
  ClientFactoryTests.swift # MODIFY: makeGitHub routing
  StatusFormatterTests.swift # MODIFY: GitHub segment/tooltip + visibility tests
```

---

### Task G1: GitHubClient

**Files:**
- Create: `Sources/MenuBarCore/GitHubClient.swift`
- Test: `Tests/MenuBarCoreTests/GitHubClientTests.swift`

**Interfaces:**
- Produces:
  - `protocol GitHubFetching: Sendable { func fetchOpenPRCount() async throws -> Int; func fetchApprovedPRCount() async throws -> Int }`
  - `enum GitHubError: Error, Equatable, CustomStringConvertible { case badResponse; case status(Int) }`
  - `struct GitHubClient: GitHubFetching, Sendable { init(host: String = "api.github.com", token: String, session: URLSession = .shared); func fetchOpenPRCount() async throws -> Int; func fetchApprovedPRCount() async throws -> Int }`

- [ ] **Step 1: Write the failing test**

`Tests/MenuBarCoreTests/GitHubClientTests.swift`:

```swift
import XCTest
@testable import MenuBarCore

final class GitHubClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func testOpenCountParsesTotalAndSendsHeaders() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url!.path, "/search/issues")
            let q = req.url!.query ?? ""
            XCTAssertTrue(q.contains("is:pr") || q.contains("is%3Apr"))
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertFalse((req.value(forHTTPHeaderField: "User-Agent") ?? "").isEmpty)
            return .init(statusCode: 200, body: Data(#"{"total_count":7,"items":[]}"#.utf8))
        }
        let client = GitHubClient(host: "api.github.com", token: "tok", session: StubURLProtocol.session())
        let count = try await client.fetchOpenPRCount()
        XCTAssertEqual(count, 7)
    }

    func testApprovedQueryIncludesReviewApproved() async throws {
        StubURLProtocol.handler = { req in
            let q = (req.url!.query ?? "").removingPercentEncoding ?? ""
            XCTAssertTrue(q.contains("review:approved"))
            return .init(statusCode: 200, body: Data(#"{"total_count":2,"items":[]}"#.utf8))
        }
        let client = GitHubClient(token: "tok", session: StubURLProtocol.session())
        XCTAssertEqual(try await client.fetchApprovedPRCount(), 2)
    }

    func testUnauthorizedMapsToStatus401() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 401, body: Data(#"{"message":"Bad credentials"}"#.utf8)) }
        let client = GitHubClient(token: "tok", session: StubURLProtocol.session())
        do {
            _ = try await client.fetchOpenPRCount()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .status(401))
        }
    }

    func testEnterpriseHostUsesApiV3Path() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url!.path, "/api/v3/search/issues")
            return .init(statusCode: 200, body: Data(#"{"total_count":0,"items":[]}"#.utf8))
        }
        let client = GitHubClient(host: "ghe.example.com", token: "tok", session: StubURLProtocol.session())
        _ = try await client.fetchOpenPRCount()
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter GitHubClientTests`
Expected: FAIL — `GitHubClient` undefined.

- [ ] **Step 3: Write the implementation**

`Sources/MenuBarCore/GitHubClient.swift`:

```swift
import Foundation

public protocol GitHubFetching: Sendable {
    func fetchOpenPRCount() async throws -> Int
    func fetchApprovedPRCount() async throws -> Int
}

public enum GitHubError: Error, Equatable, CustomStringConvertible {
    case badResponse
    case status(Int)

    public var description: String {
        switch self {
        case .badResponse: return "GitHub: niepoprawna odpowiedź"
        case .status(401): return "GitHub: token wygasł lub jest niepoprawny (401)"
        case .status(403): return "GitHub: brak dostępu lub limit zapytań (403)"
        case .status(let code): return "GitHub: błąd HTTP \(code)"
        }
    }
}

public struct GitHubClient: GitHubFetching, Sendable {
    public let host: String
    let token: String
    let session: URLSession

    public init(host: String = "api.github.com", token: String, session: URLSession = .shared) {
        self.host = host
        self.token = token
        self.session = session
    }

    static let openQuery = "is:pr is:open author:@me archived:false"
    static let approvedQuery = "is:pr is:open author:@me archived:false review:approved"

    public func fetchOpenPRCount() async throws -> Int { try await count(query: Self.openQuery) }
    public func fetchApprovedPRCount() async throws -> Int { try await count(query: Self.approvedQuery) }

    private var basePath: String { host == "api.github.com" ? "" : "/api/v3" }

    struct SearchResult: Decodable { let total_count: Int }

    private func count(query: String) async throws -> Int {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = basePath + "/search/issues"
        comps.queryItems = [
            .init(name: "q", value: query),
            .init(name: "per_page", value: "1"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("MRJiraMenuBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.badResponse }
        guard http.statusCode == 200 else { throw GitHubError.status(http.statusCode) }
        return try JSONDecoder().decode(SearchResult.self, from: data).total_count
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter GitHubClientTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarCore/GitHubClient.swift Tests/MenuBarCoreTests/GitHubClientTests.swift
git commit -m "feat: GitHubClient for open/approved PR counts via Search API"
```

---

### Task G2: AppConfig GitHub fields + SettingsStore persistence

**Files:**
- Modify: `Sources/MenuBarCore/AppConfig.swift`
- Modify: `Sources/MenuBarCore/SettingsStore.swift`
- Test: `Tests/MenuBarCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces (additions): `AppConfig.githubHost`, `AppConfig.githubToken`, `AppConfig.defaultGitHubHost`, `AppConfig.gitlabActive`, `AppConfig.jiraActive`, `AppConfig.githubActive`, `AppConfig.hasAnySource`. `isComplete` is kept unchanged.
- `SettingsStore` persists/loads the two GitHub fields.

- [ ] **Step 1: Write the failing test**

Append to `Tests/MenuBarCoreTests/SettingsStoreTests.swift` (inside the class):

```swift
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
        c.jiraToken = "jt"
        XCTAssertTrue(c.jiraActive)
        XCTAssertTrue(c.hasAnySource)
        XCTAssertFalse(c.gitlabActive)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — `githubHost`/`githubActive`/`hasAnySource` undefined.

- [ ] **Step 3: Modify `AppConfig.swift`**

Replace the struct body with the extended version (adds GitHub fields, active computeds, `hasAnySource`; keeps `isComplete`):

```swift
public struct AppConfig: Equatable, Sendable {
    public var gitlabHost: String
    public var gitlabToken: String
    public var jiraHost: String
    public var jiraToken: String
    public var githubHost: String
    public var githubToken: String

    public static let defaultGitLabHost = "drm-gitlab.redlabs.pl"
    public static let defaultJiraHost = "jira.redge.com"
    public static let defaultGitHubHost = "api.github.com"

    public init(
        gitlabHost: String = defaultGitLabHost,
        gitlabToken: String = "",
        jiraHost: String = defaultJiraHost,
        jiraToken: String = "",
        githubHost: String = defaultGitHubHost,
        githubToken: String = ""
    ) {
        self.gitlabHost = gitlabHost
        self.gitlabToken = gitlabToken
        self.jiraHost = jiraHost
        self.jiraToken = jiraToken
        self.githubHost = githubHost
        self.githubToken = githubToken
    }

    public var gitlabActive: Bool { !gitlabHost.isEmpty && !gitlabToken.isEmpty }
    public var jiraActive: Bool { !jiraHost.isEmpty && !jiraToken.isEmpty }
    public var githubActive: Bool { !githubHost.isEmpty && !githubToken.isEmpty }
    public var hasAnySource: Bool { gitlabActive || jiraActive || githubActive }

    public var isComplete: Bool {
        !gitlabHost.isEmpty && !gitlabToken.isEmpty && !jiraHost.isEmpty && !jiraToken.isEmpty
    }
}
```

(Leave the `CredentialImporting` protocol below it unchanged.)

- [ ] **Step 4: Modify `SettingsStore.swift`**

Add two keys to the private `Key` enum:

```swift
        static let githubHost = "githubHost"
        static let githubToken = "githubToken"
```

In `init`, extend the `config` assignment to load the GitHub fields:

```swift
        self.config = AppConfig(
            gitlabHost: secrets.string(forKey: Key.gitlabHost) ?? AppConfig.defaultGitLabHost,
            gitlabToken: secrets.string(forKey: Key.gitlabToken) ?? "",
            jiraHost: secrets.string(forKey: Key.jiraHost) ?? AppConfig.defaultJiraHost,
            jiraToken: secrets.string(forKey: Key.jiraToken) ?? "",
            githubHost: secrets.string(forKey: Key.githubHost) ?? AppConfig.defaultGitHubHost,
            githubToken: secrets.string(forKey: Key.githubToken) ?? ""
        )
```

In `save(_:)`, persist the GitHub fields too (add after the jira lines, before `config = newConfig`):

```swift
        try secrets.set(newConfig.githubHost, forKey: Key.githubHost)
        try secrets.set(newConfig.githubToken, forKey: Key.githubToken)
```

(`seedFromFilesIfNeeded` is unchanged — GitHub is not seeded from files.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS (all existing + 2 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarCore/AppConfig.swift Sources/MenuBarCore/SettingsStore.swift Tests/MenuBarCoreTests/SettingsStoreTests.swift
git commit -m "feat: AppConfig GitHub fields + per-source active flags, persisted in SettingsStore"
```

---

### Task G3: GitHubCounts + StatusStore third source + ClientFactory.makeGitHub

**Files:**
- Modify: `Sources/MenuBarCore/StatusStore.swift`
- Modify: `Sources/MenuBarCore/ClientFactory.swift`
- Test: `Tests/MenuBarCoreTests/StatusStoreTests.swift`, `Tests/MenuBarCoreTests/ClientFactoryTests.swift`

**Interfaces:**
- Produces:
  - `struct GitHubCounts: Equatable { let open: Int; let approved: Int }`
  - `StatusStore.github: SourceResult<GitHubCounts>` (get); `init(..., githubClient: GitHubFetching? = nil, interval:)`; `setClients(gitlabClient:jiraClient:githubClient: GitHubFetching? = nil)`.
  - `ClientFactory.makeGitHub(_ config: AppConfig) -> (any GitHubFetching)?` (nil when `!config.githubActive`). Existing `make(_:)` is unchanged.

- [ ] **Step 1: Write the failing test**

Append to `Tests/MenuBarCoreTests/StatusStoreTests.swift` (inside the class). The file already defines `MutableGitLab`/`FakeJira`; add a GitHub double at file scope (top of the file, next to the others):

```swift
private struct FakeGitHub: GitHubFetching {
    var open: Result<Int, Error>
    var approved: Result<Int, Error>
    func fetchOpenPRCount() async throws -> Int { try open.get() }
    func fetchApprovedPRCount() async throws -> Int { try approved.get() }
}
```

New test cases:

```swift
    @MainActor
    func testGitHubSourcePopulatesWhenClientPresent() async {
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(1), ready: .success(0)),
            jiraClient: FakeJira(backlog: .success(0), inProgress: .success(0)),
            githubClient: FakeGitHub(open: .success(5), approved: .success(3))
        )
        await store.refresh()
        XCTAssertEqual(store.github.value, GitHubCounts(open: 5, approved: 3))
    }

    @MainActor
    func testGitHubClearsToNeutralWhenClientNil() async {
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(1), ready: .success(0)),
            jiraClient: FakeJira(backlog: .success(0), inProgress: .success(0)),
            githubClient: FakeGitHub(open: .success(5), approved: .success(3))
        )
        await store.refresh()
        XCTAssertNotNil(store.github.value)

        store.setClients(
            gitlabClient: MutableGitLab(open: .success(1), ready: .success(0)),
            jiraClient: FakeJira(backlog: .success(0), inProgress: .success(0)),
            githubClient: nil
        )
        await store.refresh()
        XCTAssertNil(store.github.value)
        XCTAssertNil(store.github.error)
    }
```

`Tests/MenuBarCoreTests/ClientFactoryTests.swift` — add:

```swift
    func testMakeGitHubReturnsNilWhenInactiveAndClientWhenActive() {
        XCTAssertNil(ClientFactory.makeGitHub(AppConfig()))  // empty github token
        let active = AppConfig(githubHost: "api.github.com", githubToken: "t")
        XCTAssertNotNil(ClientFactory.makeGitHub(active))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter StatusStoreTests`
Expected: FAIL — `GitHubCounts`/`github`/`githubClient` undefined.

- [ ] **Step 3: Modify `StatusStore.swift`**

(a) Add the counts struct next to `GitLabCounts`/`JiraCounts`:

```swift
public struct GitHubCounts: Equatable {
    public let open: Int
    public let approved: Int
    public init(open: Int, approved: Int) { self.open = open; self.approved = approved }
}
```

(b) Add a published source + an optional client property (next to the existing `gitlab`/`jira` and `gitlabClient`/`jiraClient`):

```swift
    public private(set) var github = SourceResult<GitHubCounts>()
```
```swift
    private var githubClient: GitHubFetching?
```

(c) Extend `init` to accept the optional GitHub client (default nil keeps existing call sites compiling). Add `githubClient: GitHubFetching? = nil,` before `interval` and assign `self.githubClient = githubClient`.

(d) Extend `setClients` to take the optional GitHub client with a default:

```swift
    public func setClients(gitlabClient: GitLabFetching, jiraClient: JiraFetching, githubClient: GitHubFetching? = nil) {
        self.gitlabClient = gitlabClient
        self.jiraClient = jiraClient
        self.githubClient = githubClient
    }
```

(e) In `refresh()`, set GitHub loading/cleared and add it to the concurrent group. Replace the body up to the `await` with:

```swift
        gitlab.isLoading = true
        jira.isLoading = true
        if githubClient != nil { github.isLoading = true } else { github = SourceResult() }
        onUpdate?()
        async let g: Void = refreshGitLab()
        async let j: Void = refreshJira()
        async let gh: Void = refreshGitHub()
        _ = await (g, j, gh)
```

(f) Add `refreshGitHub()` mirroring `refreshJira()` (same cancellation guards):

```swift
    private func refreshGitHub() async {
        guard let githubClient else { return }
        do {
            async let open = githubClient.fetchOpenPRCount()
            async let approved = githubClient.fetchApprovedPRCount()
            let counts = GitHubCounts(open: try await open, approved: try await approved)

            if Task.isCancelled { return }

            github = SourceResult(value: counts, error: nil, isLoading: false)
        } catch {
            if Task.isCancelled { return }

            github = SourceResult(value: github.value, error: Self.message(error), isLoading: false)
        }
        onUpdate?()
    }
```

(g) Add `GitHubError` to the `message(_:)` switch:

```swift
        case let e as GitHubError: return e.description
```

- [ ] **Step 4: Modify `ClientFactory.swift`**

Add (keep `make(_:)` as-is):

```swift
    public static func makeGitHub(_ config: AppConfig) -> (any GitHubFetching)? {
        guard config.githubActive else { return nil }
        return GitHubClient(host: config.githubHost, token: config.githubToken)
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test`
Expected: PASS (all existing + new GitHub/ClientFactory cases).

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarCore/StatusStore.swift Sources/MenuBarCore/ClientFactory.swift Tests/MenuBarCoreTests/StatusStoreTests.swift Tests/MenuBarCoreTests/ClientFactoryTests.swift
git commit -m "feat: StatusStore GitHub source (optional client) + ClientFactory.makeGitHub"
```

---

### Task G4: Visibility-aware StatusFormatter + GitHub segments/tooltip

**Files:**
- Modify: `Sources/MenuBarCore/StatusFormatter.swift`
- Test: `Tests/MenuBarCoreTests/StatusFormatterTests.swift`

**Interfaces:**
- Produces:
  - `struct SourceVisibility: Equatable { let gitlab/github/jira: Bool; init(gitlab: Bool = true, github: Bool = false, jira: Bool = true) }`
  - `StatusFormatter.githubOpenSymbol`, `StatusFormatter.githubReadySymbol`.
  - `segments(gitlab:github:jira:visibility:)` and `tooltip(gitlab:github:jira:lastRefresh:visibility:)` — `github` and `visibility` are defaulted so old `segments(gitlab:jira:)` / `tooltip(gitlab:jira:lastRefresh:)` calls keep working and keep returning the GitLab+Jira output.

- [ ] **Step 1: Write the failing test**

Append to `Tests/MenuBarCoreTests/StatusFormatterTests.swift`:

```swift
    func testSegmentsIncludeGitHubWhenVisible() {
        let segs = StatusFormatter.segments(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            github: SourceResult(value: GitHubCounts(open: 5, approved: 3)),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 1)),
            visibility: SourceVisibility(gitlab: true, github: true, jira: true)
        )
        XCTAssertEqual(segs.map(\.text), ["8", "2", "5", "3", "4", "1"])
        XCTAssertEqual(segs[2].symbol, StatusFormatter.githubOpenSymbol)
        XCTAssertEqual(segs[3].symbol, StatusFormatter.githubReadySymbol)
    }

    func testGitHubHiddenWhenNotVisible() {
        let segs = StatusFormatter.segments(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            github: SourceResult(value: GitHubCounts(open: 5, approved: 3)),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 1)),
            visibility: SourceVisibility(gitlab: true, github: false, jira: true)
        )
        XCTAssertEqual(segs.map(\.text), ["8", "2", "4", "1"])
    }

    func testTooltipIncludesGitHubWhenVisible() {
        let tip = StatusFormatter.tooltip(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            github: SourceResult(value: GitHubCounts(open: 5, approved: 3)),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 1)),
            lastRefresh: nil,
            visibility: SourceVisibility(gitlab: true, github: true, jira: true)
        )
        XCTAssertTrue(tip.contains("GitHub: 5 PR, 3 approved"))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter StatusFormatterTests`
Expected: FAIL — `SourceVisibility`/`githubOpenSymbol` undefined.

- [ ] **Step 3: Modify `StatusFormatter.swift`**

(a) Add the visibility struct and GitHub symbols (after the existing symbol constants):

```swift
    public static let githubOpenSymbol = "arrow.triangle.pull"
    public static let githubReadySymbol = "checkmark.circle"
```

Add at file scope (e.g. above `enum StatusFormatter`):

```swift
public struct SourceVisibility: Equatable {
    public let gitlab: Bool
    public let github: Bool
    public let jira: Bool
    public init(gitlab: Bool = true, github: Bool = false, jira: Bool = true) {
        self.gitlab = gitlab
        self.github = github
        self.jira = jira
    }
}
```

(b) Replace `segments(...)` with the visibility-aware version (defaults preserve old behavior):

```swift
    public static func segments(
        gitlab: SourceResult<GitLabCounts>,
        github: SourceResult<GitHubCounts> = .init(),
        jira: SourceResult<JiraCounts>,
        visibility: SourceVisibility = .init()
    ) -> [TitleSegment] {
        var result: [TitleSegment] = []

        if visibility.gitlab {
            let e = gitlab.error != nil
            result.append(segment(symbol: mrSymbol, value: gitlab.value.map { String($0.open) }, hasError: e))
            result.append(segment(symbol: readySymbol, value: gitlab.value.map { String($0.ready) }, hasError: e))
        }
        if visibility.github {
            let e = github.error != nil
            result.append(segment(symbol: githubOpenSymbol, value: github.value.map { String($0.open) }, hasError: e))
            result.append(segment(symbol: githubReadySymbol, value: github.value.map { String($0.approved) }, hasError: e))
        }
        if visibility.jira {
            let e = jira.error != nil
            result.append(segment(symbol: backlogSymbol, value: jira.value.map { String($0.backlog) }, hasError: e))
            result.append(segment(symbol: inProgressSymbol, value: jira.value.map { String($0.inProgress) }, hasError: e))
        }
        return result
    }
```

(c) Replace `tooltip(...)` with the visibility-aware version (defaults preserve old behavior):

```swift
    public static func tooltip(
        gitlab: SourceResult<GitLabCounts>,
        github: SourceResult<GitHubCounts> = .init(),
        jira: SourceResult<JiraCounts>,
        lastRefresh: Date?,
        visibility: SourceVisibility = .init()
    ) -> String {
        var parts: [String] = []

        if visibility.gitlab {
            if let g = gitlab.value { parts.append("Moje MR: \(g.open) otwartych, \(g.ready) gotowe do mergu (≥2 approve)") }
            if let e = gitlab.error { parts.append("GitLab błąd: \(e)") }
        }
        if visibility.github {
            if let g = github.value { parts.append("GitHub: \(g.open) PR, \(g.approved) approved") }
            if let e = github.error { parts.append("GitHub błąd: \(e)") }
        }
        if visibility.jira {
            if let j = jira.value { parts.append("Jira: \(j.backlog) backlog, \(j.inProgress) w toku") }
            if let e = jira.error { parts.append("Jira błąd: \(e)") }
        }

        if let last = lastRefresh {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            parts.append("odświeżono \(f.string(from: last))")
        }

        return parts.joined(separator: " · ")
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter StatusFormatterTests`
Expected: PASS (all existing unchanged + 3 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarCore/StatusFormatter.swift Tests/MenuBarCoreTests/StatusFormatterTests.swift
git commit -m "feat: visibility-aware StatusFormatter with GitHub segments and tooltip"
```

---

### Task G5: UI wiring — Settings field, menu-bar segments, menu section

**Files:**
- Modify: `Sources/MRJiraMenuBar/SettingsView.swift`
- Modify: `Sources/MRJiraMenuBar/StatusItemController.swift`
- Modify: `Sources/MRJiraMenuBar/AppDelegate.swift`

**Interfaces:**
- Consumes: `AppConfig` (GitHub fields + active flags), `GitHubCounts`, `SourceVisibility`, `ClientFactory.makeGitHub`, `StatusStore.github`/`setClients(...:githubClient:)`, `StatusFormatter` (new signatures).
- Produces: a GitHub section in Settings, GitHub segments/menu, and AppDelegate that wires the third source. No automated tests (UI) — build + manual.

- [ ] **Step 1: Modify `SettingsView.swift`**

Add a GitHub `GroupBox` after the Jira one:

```swift
            GroupBox("GitHub") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Host") { TextField("api.github.com", text: $config.githubHost) }
                    LabeledContent("Token") { SecureField("Personal Access Token", text: $config.githubToken) }
                }.padding(6)
            }
```

Change the Save button gate from `isComplete` to `hasAnySource`:

```swift
                    .disabled(!config.hasAnySource)
```

- [ ] **Step 2: Modify `StatusItemController.swift`**

(a) Add GitHub host state + a needs-config tooltip tweak near the other `var` properties:

```swift
    var githubHost = AppConfig.defaultGitHubHost
    var githubWebHost = "github.com"
```

(b) Add a GitHub PR web URL helper (next to `mrDashboardURL`/`jiraURL`):

```swift
    private var githubPRsURL: URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = githubWebHost
        comps.path = "/pulls"
        comps.queryItems = [.init(name: "q", value: "is:open is:pr author:@me")]
        return comps.url!
    }
```

(c) Change `update(...)` to take `github` + `visibility` and forward them:

```swift
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
```

(d) Change `buildMenu(...)` to the same signature and add a GitHub section + make each section conditional on visibility. Replace the GitLab/Jira section construction with visibility guards and insert GitHub between them:

```swift
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
```

(e) Update the needs-config tooltip text to mention all three (optional polish):

```swift
        button.toolTip = "Skonfiguruj tokeny (GitLab / GitHub / Jira) w Ustawieniach"
```

- [ ] **Step 3: Modify `AppDelegate.swift`**

(a) Add a `visibility` helper computed property:

```swift
    private var visibility: SourceVisibility {
        let c = settings.config
        return SourceVisibility(gitlab: c.gitlabActive, github: c.githubActive, jira: c.jiraActive)
    }
```

(b) Update the `onUpdate` closure to pass `github` + `visibility`:

```swift
        store.onUpdate = { [weak self] in
            guard let self else { return }
            self.controller.update(
                gitlab: self.store.gitlab,
                github: self.store.github,
                jira: self.store.jira,
                lastRefresh: self.store.lastRefresh,
                visibility: self.visibility
            )
        }
```

(c) In `applyConfig()`, set GitHub hosts on the controller, gate on `hasAnySource`, and build/pass the GitHub client:

```swift
    private func applyConfig() {
        let config = settings.config
        controller.gitlabHost = config.gitlabHost
        controller.jiraHost = config.jiraHost
        controller.githubHost = config.githubHost
        controller.githubWebHost = config.githubHost == "api.github.com" ? "github.com" : config.githubHost

        guard config.hasAnySource else {
            store.stop()
            store.setClients(
                gitlabClient: FailingGitLab(error: AppError.notConfigured),
                jiraClient: FailingJira(error: AppError.notConfigured),
                githubClient: nil
            )
            controller.showNeedsConfig()
            openSettings()
            return
        }

        let (gitlab, jira) = ClientFactory.make(config)
        store.setClients(gitlabClient: gitlab, jiraClient: jira, githubClient: ClientFactory.makeGitHub(config))
        controller.markConfigured()
        store.scheduleTimer()
        store.restartRefresh()
    }
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!` no errors.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 6: Manual verification**

Run: `swift run MRJiraMenuBar`
Expected:
- Menu → "Ustawienia…": now shows a third **GitHub** section (Host prefilled `api.github.com`, Token masked).
- Paste a valid GitHub PAT (scopes: `repo` + `read:org` for private orgs) → Save → two extra menu-bar segments appear (pull-request icon + open count, check-circle + approved count) between GitLab and Jira, and a "GitHub — moje PR" menu section with a link to your PR list.
- Leave the GitHub token empty → no GitHub segments/section appear; GitLab+Jira behave exactly as before.
- A bad GitHub token shows the GitHub error symbol/row only; GitLab and Jira keep working.

- [ ] **Step 7: Commit**

```bash
git add Sources/MRJiraMenuBar
git commit -m "feat: GitHub settings field, menu-bar segments, and menu section"
```

---

## Self-Review

- GitHub open + approved counts → G1 (`GitHubClient`), shown via G4/G5. ✓
- Configured in Settings + Keychain → G2 (`AppConfig`/`SettingsStore`), G5 (`SettingsView`). ✓
- Separate GitHub icons on the bar → G4 symbols + G5 segments. ✓
- Per-source independence / hidden when unconfigured → `*Active` (G2), optional client (G3), `SourceVisibility` (G4), wiring (G5). ✓
- Needs-config only when nothing configured → `hasAnySource` gate (G2 + G5). ✓
- No `gh` seeding → `seedFromFilesIfNeeded` left unchanged (G2). ✓
- Enterprise host path + required headers/User-Agent → G1. ✓
- Backward compatibility (43 tests) → defaults on every new parameter (G3 init/setClients, G4 segments/tooltip); `make(_:)` unchanged. ✓
- Type consistency: `GitHubFetching` (G1) → `StatusStore`/`ClientFactory` (G3); `GitHubCounts` (G3) → `StatusFormatter` (G4) → controller (G5); `SourceVisibility` (G4) → controller/AppDelegate (G5). ✓
