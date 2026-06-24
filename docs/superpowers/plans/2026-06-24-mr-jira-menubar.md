# MR/Jira Menu Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app showing four live counters — my open MRs, my MRs ready to merge (≥2 approvals), my Jira backlog (To Do/Backlog), and my Jira in-progress — fetched from drm-gitlab and jira.redge.com.

**Architecture:** Swift Package with two targets. `MenuBarCore` (Foundation-only library) holds all testable logic: credential reading, GitLab/Jira API clients, the refresh store, and the display formatter. `MRJiraMenuBar` (AppKit executable) owns the `NSStatusItem`, renders the title with SF Symbols, sets the hover tooltip, builds the dropdown menu, and wires the store to the UI. The app runs as an agent (`.accessory` activation policy): no Dock icon, no window.

**Tech Stack:** Swift 5.9, Swift Package Manager, AppKit (`NSStatusItem`), `URLSession`, XCTest. No third-party dependencies.

## Global Constraints

- Target platform: **macOS 13+** (`platforms: [.macOS(.v13)]`).
- **No third-party dependencies.** Foundation + AppKit only.
- `MenuBarCore` must **not import AppKit** (keep it pure/testable). AppKit lives only in the executable target.
- Tokens read from existing files; held in memory only; never logged:
  - GitLab: `~/Library/Application Support/glab-cli/config.yml`, host `drm-gitlab.redlabs.pl`.
  - Jira: `~/.claude/.secrets/jira-token`.
- GitLab host: `drm-gitlab.redlabs.pl`. Jira host: `jira.redge.com`.
- Approval threshold for "ready to merge": **2**.
- Default refresh interval: **300 seconds**.
- Jira JQL (verbatim):
  - Backlog: `assignee = currentUser() AND resolution = Unresolved AND status in ("To Do", "Backlog")`
  - In progress: `assignee = currentUser() AND resolution = Unresolved AND status = "In Progress"`

## File Structure

```
mr-jira-menubar/
  Package.swift
  Sources/
    MenuBarCore/
      Credentials.swift          # read tokens from glab yaml + jira file
      GitLabClient.swift         # open MR count + ready-to-merge count
      JiraClient.swift           # count(jql:) + backlog/inProgress
      StatusStore.swift          # concurrent refresh, error isolation, timer, onUpdate
      StatusFormatter.swift      # pure title segments + tooltip string
    MRJiraMenuBar/
      main.swift                 # NSApplication + .accessory policy
      AppDelegate.swift          # wires Credentials → clients → store → controller
      StatusItemController.swift # NSStatusItem: attributedTitle, toolTip, NSMenu, links
  Tests/
    MenuBarCoreTests/
      Support/StubURLProtocol.swift
      CredentialsTests.swift
      GitLabClientTests.swift
      JiraClientTests.swift
      StatusStoreTests.swift
      StatusFormatterTests.swift
```

---

### Task 1: Package scaffold + Credentials

**Files:**
- Create: `Package.swift`
- Create: `Sources/MenuBarCore/Credentials.swift`
- Test: `Tests/MenuBarCoreTests/CredentialsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum CredentialsError: Error, CustomStringConvertible, Equatable { case fileMissing(String); case hostMissing(String, file: String); case tokenMissing(String, file: String) }`
  - `struct Credentials { init(glabConfigPath: String = <default>, jiraTokenPath: String = <default>); func jiraToken() throws -> String; func gitlabToken(host: String = "drm-gitlab.redlabs.pl") throws -> String; static func parseToken(host: String, yaml: String, file: String) throws -> String }`

- [ ] **Step 1: Create the package manifest**

`Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MRJiraMenuBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MenuBarCore"),
        .executableTarget(name: "MRJiraMenuBar", dependencies: ["MenuBarCore"]),
        .testTarget(name: "MenuBarCoreTests", dependencies: ["MenuBarCore"]),
    ]
)
```

Also create a minimal placeholder so the executable target compiles:
`Sources/MRJiraMenuBar/main.swift`:

```swift
// Replaced in Task 7.
print("MRJiraMenuBar placeholder")
```

- [ ] **Step 2: Write the failing test**

`Tests/MenuBarCoreTests/CredentialsTests.swift`:

```swift
import XCTest
@testable import MenuBarCore

final class CredentialsTests: XCTestCase {
    let sampleYAML = """
    hosts:
        gitlab.com:
            token: WRONGTOKEN
            user: someone
        drm-gitlab.redlabs.pl:
            api_host: drm-gitlab.redlabs.pl
            user: bartlomiej.zimny
            token: GLPAT-correct-123
    """

    func testParsesTokenForRequestedHost() throws {
        let token = try Credentials.parseToken(host: "drm-gitlab.redlabs.pl", yaml: sampleYAML, file: "f")
        XCTAssertEqual(token, "GLPAT-correct-123")
    }

    func testThrowsHostMissingWithPath() {
        XCTAssertThrowsError(try Credentials.parseToken(host: "no.such.host", yaml: sampleYAML, file: "/p/config.yml")) { error in
            XCTAssertEqual(error as? CredentialsError, .hostMissing("no.such.host", file: "/p/config.yml"))
        }
    }

    func testJiraTokenTrimsWhitespace() throws {
        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("jira-token-test")
        try "  abc123\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let creds = Credentials(glabConfigPath: "/nonexistent", jiraTokenPath: path)
        XCTAssertEqual(try creds.jiraToken(), "abc123")
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter CredentialsTests`
Expected: FAIL — `Credentials` / `CredentialsError` undefined (build error).

- [ ] **Step 4: Write the implementation**

`Sources/MenuBarCore/Credentials.swift`:

```swift
import Foundation

public enum CredentialsError: Error, CustomStringConvertible, Equatable {
    case fileMissing(String)
    case hostMissing(String, file: String)
    case tokenMissing(String, file: String)

    public var description: String {
        switch self {
        case .fileMissing(let p): return "Brak pliku: \(p)"
        case .hostMissing(let h, let f): return "Brak hosta \(h) w \(f)"
        case .tokenMissing(let h, let f): return "Brak tokenu dla \(h) w \(f)"
        }
    }
}

public struct Credentials {
    let glabConfigPath: String
    let jiraTokenPath: String

    public init(
        glabConfigPath: String = (("~/Library/Application Support/glab-cli/config.yml") as NSString).expandingTildeInPath,
        jiraTokenPath: String = (("~/.claude/.secrets/jira-token") as NSString).expandingTildeInPath
    ) {
        self.glabConfigPath = glabConfigPath
        self.jiraTokenPath = jiraTokenPath
    }

    public func jiraToken() throws -> String {
        guard let data = FileManager.default.contents(atPath: jiraTokenPath),
              let raw = String(data: data, encoding: .utf8) else {
            throw CredentialsError.fileMissing(jiraTokenPath)
        }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw CredentialsError.fileMissing(jiraTokenPath) }
        return token
    }

    public func gitlabToken(host: String = "drm-gitlab.redlabs.pl") throws -> String {
        guard let data = FileManager.default.contents(atPath: glabConfigPath),
              let content = String(data: data, encoding: .utf8) else {
            throw CredentialsError.fileMissing(glabConfigPath)
        }
        return try Self.parseToken(host: host, yaml: content, file: glabConfigPath)
    }

    public static func parseToken(host: String, yaml: String, file: String) throws -> String {
        let lines = yaml.components(separatedBy: .newlines)
        var inHost = false
        var hostIndent = -1
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix { $0 == " " }.count

            if !inHost {
                if trimmed == "\(host):" {
                    inHost = true
                    hostIndent = indent
                }
                continue
            }

            if !trimmed.isEmpty && indent <= hostIndent {
                break
            }

            if trimmed.hasPrefix("token:") {
                let value = trimmed.dropFirst("token:".count).trimmingCharacters(in: .whitespaces)
                let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if cleaned.isEmpty {
                    throw CredentialsError.tokenMissing(host, file: file)
                }
                return cleaned
            }
        }

        if inHost {
            throw CredentialsError.tokenMissing(host, file: file)
        }
        throw CredentialsError.hostMissing(host, file: file)
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter CredentialsTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: package scaffold + credentials reader"
```

---

### Task 2: GitLab open-MR count + HTTP test stub

**Files:**
- Create: `Sources/MenuBarCore/GitLabClient.swift`
- Create: `Tests/MenuBarCoreTests/Support/StubURLProtocol.swift`
- Test: `Tests/MenuBarCoreTests/GitLabClientTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `protocol GitLabFetching { func fetchOpenMRCount() async throws -> Int; func fetchReadyToMergeCount() async throws -> Int }`
  - `enum GitLabError: Error, Equatable { case badResponse; case missingTotal; case status(Int) }`
  - `struct GitLabClient: GitLabFetching { init(host: String, token: String, session: URLSession = .shared, approvalThreshold: Int = 2); func fetchOpenMRCount() async throws -> Int; func fetchReadyToMergeCount() async throws -> Int }` (only `fetchOpenMRCount` implemented in this task; `fetchReadyToMergeCount` filled in Task 3)
  - Test helper `StubURLProtocol` with `static var handler: ((URLRequest) -> StubURLProtocol.Stub)?` and `static func session() -> URLSession`.

- [ ] **Step 1: Write the HTTP stub support**

`Tests/MenuBarCoreTests/Support/StubURLProtocol.swift`:

```swift
import Foundation

final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }
    }

    static var handler: ((URLRequest) -> Stub)?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let stub = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
```

- [ ] **Step 2: Write the failing test**

`Tests/MenuBarCoreTests/GitLabClientTests.swift`:

```swift
import XCTest
@testable import MenuBarCore

final class GitLabClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func testFetchOpenMRCountReadsXTotalHeader() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url!.path, "/api/v4/merge_requests")
            XCTAssertTrue(req.url!.query!.contains("scope=created_by_me"))
            XCTAssertEqual(req.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "tok")
            return .init(statusCode: 200, headers: ["X-Total": "8"], body: Data("[]".utf8))
        }
        let client = GitLabClient(host: "gl.example", token: "tok", session: StubURLProtocol.session())
        let count = try await client.fetchOpenMRCount()
        XCTAssertEqual(count, 8)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter GitLabClientTests`
Expected: FAIL — `GitLabClient` undefined (build error).

- [ ] **Step 4: Write the implementation**

`Sources/MenuBarCore/GitLabClient.swift`:

```swift
import Foundation

public protocol GitLabFetching {
    func fetchOpenMRCount() async throws -> Int
    func fetchReadyToMergeCount() async throws -> Int
}

public enum GitLabError: Error, Equatable {
    case badResponse
    case missingTotal
    case status(Int)
}

public struct GitLabClient: GitLabFetching {
    public let host: String
    let token: String
    let session: URLSession
    let approvalThreshold: Int

    public init(host: String, token: String, session: URLSession = .shared, approvalThreshold: Int = 2) {
        self.host = host
        self.token = token
        self.session = session
        self.approvalThreshold = approvalThreshold
    }

    func request(_ path: String, query: [URLQueryItem]) -> URLRequest {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = "/api/v4" + path
        comps.queryItems = query.isEmpty ? nil : query
        var req = URLRequest(url: comps.url!)
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        return req
    }

    public func fetchOpenMRCount() async throws -> Int {
        let req = request("/merge_requests", query: [
            .init(name: "scope", value: "created_by_me"),
            .init(name: "state", value: "opened"),
            .init(name: "per_page", value: "1"),
        ])
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GitLabError.badResponse }
        guard http.statusCode == 200 else { throw GitLabError.status(http.statusCode) }
        guard let total = http.value(forHTTPHeaderField: "X-Total"), let n = Int(total) else {
            throw GitLabError.missingTotal
        }
        return n
    }

    public func fetchReadyToMergeCount() async throws -> Int {
        // Implemented in Task 3.
        0
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter GitLabClientTests`
Expected: PASS (1 test).

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarCore/GitLabClient.swift Tests/MenuBarCoreTests
git commit -m "feat: gitlab open-MR count + http test stub"
```

---

### Task 3: GitLab ready-to-merge count (≥2 approvals)

**Files:**
- Modify: `Sources/MenuBarCore/GitLabClient.swift`
- Test: `Tests/MenuBarCoreTests/GitLabClientTests.swift`

**Interfaces:**
- Consumes: `GitLabClient.request(_:query:)`, `GitLabError`, `StubURLProtocol`.
- Produces: working `GitLabClient.fetchReadyToMergeCount() async throws -> Int` (lists my open MRs with pagination, then counts those with `approved_by.count >= approvalThreshold` via concurrent approvals calls).

- [ ] **Step 1: Write the failing test**

Append to `Tests/MenuBarCoreTests/GitLabClientTests.swift` (inside the class):

```swift
    func testReadyToMergeCountsOnlyMRsWithTwoApprovals() async throws {
        StubURLProtocol.handler = { req in
            let path = req.url!.path
            if path.contains("/merge_requests/10/approvals") {
                return .init(statusCode: 200, body: Data(#"{"approved_by":[{"user":{}},{"user":{}}]}"#.utf8))
            }
            if path.contains("/merge_requests/11/approvals") {
                return .init(statusCode: 200, body: Data(#"{"approved_by":[{"user":{}}]}"#.utf8))
            }
            if path == "/api/v4/merge_requests" {
                return .init(statusCode: 200, body: Data(#"[{"project_id":1,"iid":10},{"project_id":1,"iid":11}]"#.utf8))
            }
            return .init(statusCode: 404)
        }
        let client = GitLabClient(host: "gl.example", token: "tok", session: StubURLProtocol.session())
        let count = try await client.fetchReadyToMergeCount()
        XCTAssertEqual(count, 1)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter GitLabClientTests/testReadyToMergeCountsOnlyMRsWithTwoApprovals`
Expected: FAIL — returns 0, expected 1.

- [ ] **Step 3: Write the implementation**

Replace the placeholder `fetchReadyToMergeCount` in `Sources/MenuBarCore/GitLabClient.swift` and add the helpers/types:

```swift
    struct MRRef: Decodable { let project_id: Int; let iid: Int }
    struct Approvals: Decodable { let approved_by: [ApprovedBy] }
    struct ApprovedBy: Decodable {}

    public func fetchReadyToMergeCount() async throws -> Int {
        let mrs = try await fetchMyOpenMRs()
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            for mr in mrs {
                group.addTask { try await self.isReady(mr) }
            }
            var count = 0
            for try await ready in group where ready { count += 1 }
            return count
        }
    }

    func fetchMyOpenMRs() async throws -> [MRRef] {
        var page = 1
        var result: [MRRef] = []
        while true {
            let req = request("/merge_requests", query: [
                .init(name: "scope", value: "created_by_me"),
                .init(name: "state", value: "opened"),
                .init(name: "per_page", value: "100"),
                .init(name: "page", value: String(page)),
            ])
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw GitLabError.badResponse
            }
            result.append(contentsOf: try JSONDecoder().decode([MRRef].self, from: data))
            guard let next = http.value(forHTTPHeaderField: "X-Next-Page"),
                  !next.isEmpty, let np = Int(next) else { break }
            page = np
        }
        return result
    }

    func isReady(_ mr: MRRef) async throws -> Bool {
        let req = request("/projects/\(mr.project_id)/merge_requests/\(mr.iid)/approvals", query: [])
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitLabError.badResponse
        }
        return try JSONDecoder().decode(Approvals.self, from: data).approved_by.count >= approvalThreshold
    }
```

(Delete the old `// Implemented in Task 3.` placeholder body.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter GitLabClientTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarCore/GitLabClient.swift Tests/MenuBarCoreTests/GitLabClientTests.swift
git commit -m "feat: gitlab ready-to-merge count via approvals"
```

---

### Task 4: Jira client

**Files:**
- Create: `Sources/MenuBarCore/JiraClient.swift`
- Test: `Tests/MenuBarCoreTests/JiraClientTests.swift`

**Interfaces:**
- Consumes: `StubURLProtocol`.
- Produces:
  - `protocol JiraFetching { func backlogCount() async throws -> Int; func inProgressCount() async throws -> Int }`
  - `enum JiraError: Error, Equatable { case badResponse }`
  - `struct JiraClient: JiraFetching { static let backlogJQL: String; static let inProgressJQL: String; init(host: String, token: String, session: URLSession = .shared); func count(jql: String) async throws -> Int; func backlogCount() async throws -> Int; func inProgressCount() async throws -> Int }`

- [ ] **Step 1: Write the failing test**

`Tests/MenuBarCoreTests/JiraClientTests.swift`:

```swift
import XCTest
@testable import MenuBarCore

final class JiraClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func testCountParsesTotalAndSendsBearer() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url!.path, "/rest/api/2/search")
            XCTAssertTrue(req.url!.query!.contains("maxResults=0"))
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            return .init(statusCode: 200, body: Data(#"{"total":4}"#.utf8))
        }
        let client = JiraClient(host: "jira.example", token: "tok", session: StubURLProtocol.session())
        let count = try await client.count(jql: "anything")
        XCTAssertEqual(count, 4)
    }

    func testBacklogJQLMatchesSpec() {
        XCTAssertEqual(
            JiraClient.backlogJQL,
            #"assignee = currentUser() AND resolution = Unresolved AND status in ("To Do", "Backlog")"#
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter JiraClientTests`
Expected: FAIL — `JiraClient` undefined (build error).

- [ ] **Step 3: Write the implementation**

`Sources/MenuBarCore/JiraClient.swift`:

```swift
import Foundation

public protocol JiraFetching {
    func backlogCount() async throws -> Int
    func inProgressCount() async throws -> Int
}

public enum JiraError: Error, Equatable {
    case badResponse
}

public struct JiraClient: JiraFetching {
    public static let backlogJQL =
        #"assignee = currentUser() AND resolution = Unresolved AND status in ("To Do", "Backlog")"#
    public static let inProgressJQL =
        #"assignee = currentUser() AND resolution = Unresolved AND status = "In Progress""#

    public let host: String
    let token: String
    let session: URLSession

    public init(host: String, token: String, session: URLSession = .shared) {
        self.host = host
        self.token = token
        self.session = session
    }

    struct SearchResult: Decodable { let total: Int }

    public func count(jql: String) async throws -> Int {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = "/rest/api/2/search"
        comps.queryItems = [
            .init(name: "jql", value: jql),
            .init(name: "maxResults", value: "0"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw JiraError.badResponse
        }
        return try JSONDecoder().decode(SearchResult.self, from: data).total
    }

    public func backlogCount() async throws -> Int { try await count(jql: Self.backlogJQL) }
    public func inProgressCount() async throws -> Int { try await count(jql: Self.inProgressJQL) }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter JiraClientTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarCore/JiraClient.swift Tests/MenuBarCoreTests/JiraClientTests.swift
git commit -m "feat: jira count client with backlog/in-progress JQL"
```

---

### Task 5: StatusStore (concurrent refresh, error isolation, retention)

**Files:**
- Create: `Sources/MenuBarCore/StatusStore.swift`
- Test: `Tests/MenuBarCoreTests/StatusStoreTests.swift`

**Interfaces:**
- Consumes: `GitLabFetching`, `JiraFetching`.
- Produces:
  - `struct GitLabCounts: Equatable { let open: Int; let ready: Int }`
  - `struct JiraCounts: Equatable { let backlog: Int; let inProgress: Int }`
  - `struct SourceResult<T: Equatable>: Equatable { var value: T?; var error: String?; var isLoading: Bool; init(value:error:isLoading:) }`
  - `@MainActor final class StatusStore { var gitlab: SourceResult<GitLabCounts> (get); var jira: SourceResult<JiraCounts> (get); var lastRefresh: Date? (get); var onUpdate: (@MainActor () -> Void)?; init(gitlabClient: GitLabFetching, jiraClient: JiraFetching, interval: TimeInterval = 300); func start(); func refreshNow(); func refresh() async; static func message(_ error: Error) -> String }`

- [ ] **Step 1: Write the failing test**

`Tests/MenuBarCoreTests/StatusStoreTests.swift`:

```swift
import XCTest
@testable import MenuBarCore

private final class MutableGitLab: GitLabFetching {
    var open: Result<Int, Error>
    var ready: Result<Int, Error>
    init(open: Result<Int, Error>, ready: Result<Int, Error>) { self.open = open; self.ready = ready }
    func fetchOpenMRCount() async throws -> Int { try open.get() }
    func fetchReadyToMergeCount() async throws -> Int { try ready.get() }
}

private struct FakeJira: JiraFetching {
    var backlog: Result<Int, Error>
    var inProgress: Result<Int, Error>
    func backlogCount() async throws -> Int { try backlog.get() }
    func inProgressCount() async throws -> Int { try inProgress.get() }
}

private enum TestError: Error { case boom }

final class StatusStoreTests: XCTestCase {
    @MainActor
    func testSuccessPopulatesBothSources() async {
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(8), ready: .success(2)),
            jiraClient: FakeJira(backlog: .success(4), inProgress: .success(3))
        )
        await store.refresh()
        XCTAssertEqual(store.gitlab.value, GitLabCounts(open: 8, ready: 2))
        XCTAssertEqual(store.jira.value, JiraCounts(backlog: 4, inProgress: 3))
        XCTAssertNotNil(store.lastRefresh)
    }

    @MainActor
    func testGitLabErrorRetainsLastValueAndLeavesJiraIntact() async {
        let gl = MutableGitLab(open: .success(8), ready: .success(2))
        let store = StatusStore(
            gitlabClient: gl,
            jiraClient: FakeJira(backlog: .success(4), inProgress: .success(3))
        )
        await store.refresh()
        gl.open = .failure(TestError.boom)
        await store.refresh()
        XCTAssertEqual(store.gitlab.value, GitLabCounts(open: 8, ready: 2))
        XCTAssertNotNil(store.gitlab.error)
        XCTAssertEqual(store.jira.value, JiraCounts(backlog: 4, inProgress: 3))
        XCTAssertNil(store.jira.error)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter StatusStoreTests`
Expected: FAIL — `StatusStore` / `GitLabCounts` / `SourceResult` undefined (build error).

- [ ] **Step 3: Write the implementation**

`Sources/MenuBarCore/StatusStore.swift`:

```swift
import Foundation

public struct GitLabCounts: Equatable {
    public let open: Int
    public let ready: Int
    public init(open: Int, ready: Int) { self.open = open; self.ready = ready }
}

public struct JiraCounts: Equatable {
    public let backlog: Int
    public let inProgress: Int
    public init(backlog: Int, inProgress: Int) { self.backlog = backlog; self.inProgress = inProgress }
}

public struct SourceResult<T: Equatable>: Equatable {
    public var value: T?
    public var error: String?
    public var isLoading: Bool
    public init(value: T? = nil, error: String? = nil, isLoading: Bool = false) {
        self.value = value
        self.error = error
        self.isLoading = isLoading
    }
}

@MainActor
public final class StatusStore {
    public private(set) var gitlab = SourceResult<GitLabCounts>()
    public private(set) var jira = SourceResult<JiraCounts>()
    public private(set) var lastRefresh: Date?
    public var onUpdate: (@MainActor () -> Void)?

    private let gitlabClient: GitLabFetching
    private let jiraClient: JiraFetching
    private let interval: TimeInterval
    private var timer: Timer?

    public init(gitlabClient: GitLabFetching, jiraClient: JiraFetching, interval: TimeInterval = 300) {
        self.gitlabClient = gitlabClient
        self.jiraClient = jiraClient
        self.interval = interval
    }

    public func start() {
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }

    public func refreshNow() {
        Task { await refresh() }
    }

    public func refresh() async {
        gitlab.isLoading = true
        jira.isLoading = true
        onUpdate?()
        async let g: Void = refreshGitLab()
        async let j: Void = refreshJira()
        _ = await (g, j)
        lastRefresh = Date()
        onUpdate?()
    }

    private func refreshGitLab() async {
        do {
            async let open = gitlabClient.fetchOpenMRCount()
            async let ready = gitlabClient.fetchReadyToMergeCount()
            gitlab = SourceResult(value: GitLabCounts(open: try await open, ready: try await ready),
                                  error: nil, isLoading: false)
        } catch {
            gitlab = SourceResult(value: gitlab.value, error: Self.message(error), isLoading: false)
        }
        onUpdate?()
    }

    private func refreshJira() async {
        do {
            async let backlog = jiraClient.backlogCount()
            async let inProgress = jiraClient.inProgressCount()
            jira = SourceResult(value: JiraCounts(backlog: try await backlog, inProgress: try await inProgress),
                                error: nil, isLoading: false)
        } catch {
            jira = SourceResult(value: jira.value, error: Self.message(error), isLoading: false)
        }
        onUpdate?()
    }

    public static func message(_ error: Error) -> String {
        if let e = error as? CustomStringConvertible { return e.description }
        return error.localizedDescription
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter StatusStoreTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarCore/StatusStore.swift Tests/MenuBarCoreTests/StatusStoreTests.swift
git commit -m "feat: status store with concurrent refresh and error isolation"
```

---

### Task 6: StatusFormatter (title segments + tooltip)

**Files:**
- Create: `Sources/MenuBarCore/StatusFormatter.swift`
- Test: `Tests/MenuBarCoreTests/StatusFormatterTests.swift`

**Interfaces:**
- Consumes: `SourceResult`, `GitLabCounts`, `JiraCounts`.
- Produces:
  - `struct TitleSegment: Equatable { let symbol: String; let text: String }`
  - `enum StatusFormatter { static let mrSymbol/readySymbol/backlogSymbol/inProgressSymbol: String; static func segments(gitlab:jira:) -> [TitleSegment]; static func tooltip(gitlab:jira:lastRefresh:) -> String }`

- [ ] **Step 1: Write the failing test**

`Tests/MenuBarCoreTests/StatusFormatterTests.swift`:

```swift
import XCTest
@testable import MenuBarCore

final class StatusFormatterTests: XCTestCase {
    func testSegmentsShowFourCountsInOrder() {
        let segs = StatusFormatter.segments(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 3))
        )
        XCTAssertEqual(segs.map(\.text), ["8", "2", "4", "3"])
        XCTAssertEqual(segs.map(\.symbol), [
            StatusFormatter.mrSymbol,
            StatusFormatter.readySymbol,
            StatusFormatter.backlogSymbol,
            StatusFormatter.inProgressSymbol,
        ])
    }

    func testSegmentsShowDashForErroredSource() {
        let segs = StatusFormatter.segments(
            gitlab: SourceResult(value: nil, error: "boom"),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 3))
        )
        XCTAssertEqual(segs[0].text, "—")
        XCTAssertEqual(segs[1].text, "—")
        XCTAssertEqual(segs[2].text, "4")
    }

    func testTooltipMentionsBothSources() {
        let tip = StatusFormatter.tooltip(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 3)),
            lastRefresh: nil
        )
        XCTAssertTrue(tip.contains("Moje MR: 8 otwartych, 2 gotowe do mergu (≥2 approve)"))
        XCTAssertTrue(tip.contains("Jira: 4 backlog, 3 w toku"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter StatusFormatterTests`
Expected: FAIL — `StatusFormatter` / `TitleSegment` undefined (build error).

- [ ] **Step 3: Write the implementation**

`Sources/MenuBarCore/StatusFormatter.swift`:

```swift
import Foundation

public struct TitleSegment: Equatable {
    public let symbol: String
    public let text: String
    public init(symbol: String, text: String) { self.symbol = symbol; self.text = text }
}

public enum StatusFormatter {
    public static let mrSymbol = "arrow.triangle.merge"
    public static let readySymbol = "checkmark.seal"
    public static let backlogSymbol = "tray.full"
    public static let inProgressSymbol = "bolt"

    static let errorText = "—"
    static let loadingText = "…"

    static func text(_ value: String?, hasError: Bool) -> String {
        if let value { return value }
        return hasError ? errorText : loadingText
    }

    public static func segments(gitlab: SourceResult<GitLabCounts>, jira: SourceResult<JiraCounts>) -> [TitleSegment] {
        let glError = gitlab.error != nil
        let jiraError = jira.error != nil
        return [
            TitleSegment(symbol: mrSymbol, text: text(gitlab.value.map { String($0.open) }, hasError: glError)),
            TitleSegment(symbol: readySymbol, text: text(gitlab.value.map { String($0.ready) }, hasError: glError)),
            TitleSegment(symbol: backlogSymbol, text: text(jira.value.map { String($0.backlog) }, hasError: jiraError)),
            TitleSegment(symbol: inProgressSymbol, text: text(jira.value.map { String($0.inProgress) }, hasError: jiraError)),
        ]
    }

    public static func tooltip(
        gitlab: SourceResult<GitLabCounts>,
        jira: SourceResult<JiraCounts>,
        lastRefresh: Date?
    ) -> String {
        var parts: [String] = []

        if let g = gitlab.value {
            parts.append("Moje MR: \(g.open) otwartych, \(g.ready) gotowe do mergu (≥2 approve)")
        } else if let e = gitlab.error {
            parts.append("GitLab błąd: \(e)")
        }

        if let j = jira.value {
            parts.append("Jira: \(j.backlog) backlog, \(j.inProgress) w toku")
        } else if let e = jira.error {
            parts.append("Jira błąd: \(e)")
        }

        if let last = lastRefresh {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            parts.append("odświeżono \(f.string(from: last))")
        }

        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter StatusFormatterTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS (all tests across the 5 test files).

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuBarCore/StatusFormatter.swift Tests/MenuBarCoreTests/StatusFormatterTests.swift
git commit -m "feat: status formatter for title segments and tooltip"
```

---

### Task 7: Menu bar app (NSStatusItem) — executable wiring

**Files:**
- Modify: `Sources/MRJiraMenuBar/main.swift`
- Create: `Sources/MRJiraMenuBar/AppDelegate.swift`
- Create: `Sources/MRJiraMenuBar/StatusItemController.swift`

**Interfaces:**
- Consumes: `Credentials`, `GitLabClient`, `JiraClient`, `StatusStore`, `StatusFormatter`, `TitleSegment`, `SourceResult`, `GitLabCounts`, `JiraCounts`.
- Produces: a runnable agent app. No automated tests (AppKit UI) — verified manually.

- [ ] **Step 1: Write the status item controller**

`Sources/MRJiraMenuBar/StatusItemController.swift`:

```swift
import AppKit
import MenuBarCore

final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onRefresh: (() -> Void)?

    private let mrDashboardURL = URL(string:
        "https://drm-gitlab.redlabs.pl/dashboard/merge_requests?scope=created_by_me&state=opened")!

    func update(gitlab: SourceResult<GitLabCounts>, jira: SourceResult<JiraCounts>, lastRefresh: Date?) {
        guard let button = statusItem.button else { return }
        button.attributedTitle = Self.attributedTitle(StatusFormatter.segments(gitlab: gitlab, jira: jira))
        button.toolTip = StatusFormatter.tooltip(gitlab: gitlab, jira: jira, lastRefresh: lastRefresh)
        statusItem.menu = buildMenu(gitlab: gitlab, jira: jira, lastRefresh: lastRefresh)
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

    private func buildMenu(gitlab: SourceResult<GitLabCounts>, jira: SourceResult<JiraCounts>, lastRefresh: Date?) -> NSMenu {
        let menu = NSMenu()

        menu.addItem(header("GitLab — moje MR"))
        let openText = gitlab.value.map { String($0.open) } ?? (gitlab.error != nil ? "—" : "…")
        let readyText = gitlab.value.map { String($0.ready) } ?? (gitlab.error != nil ? "—" : "…")
        menu.addItem(link("  Otwarte: \(openText)", url: mrDashboardURL))
        menu.addItem(link("  Gotowe do mergu: \(readyText)", url: mrDashboardURL))
        if let e = gitlab.error { menu.addItem(NSMenuItem(title: "  Błąd: \(e)", action: nil, keyEquivalent: "")) }

        menu.addItem(.separator())
        menu.addItem(header("Jira"))
        let backlogText = jira.value.map { String($0.backlog) } ?? (jira.error != nil ? "—" : "…")
        let progText = jira.value.map { String($0.inProgress) } ?? (jira.error != nil ? "—" : "…")
        menu.addItem(link("  Backlog: \(backlogText)", url: Self.jiraURL(JiraClient.backlogJQL)))
        menu.addItem(link("  W toku: \(progText)", url: Self.jiraURL(JiraClient.inProgressJQL)))
        if let e = jira.error { menu.addItem(NSMenuItem(title: "  Błąd: \(e)", action: nil, keyEquivalent: "")) }

        menu.addItem(.separator())
        if let last = lastRefresh {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            menu.addItem(NSMenuItem(title: "Ostatnie odświeżenie: \(f.string(from: last))", action: nil, keyEquivalent: ""))
        }
        let refreshItem = NSMenuItem(title: "Odśwież teraz", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
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

    static func jiraURL(_ jql: String) -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "jira.redge.com"
        comps.path = "/issues/"
        comps.queryItems = [.init(name: "jql", value: jql)]
        return comps.url!
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func refresh() { onRefresh?() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
```

- [ ] **Step 2: Write the app delegate**

`Sources/MRJiraMenuBar/AppDelegate.swift`:

```swift
import AppKit
import MenuBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: StatusStore?
    private let controller = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let creds = Credentials()
        do {
            let gitlab = GitLabClient(host: "drm-gitlab.redlabs.pl", token: try creds.gitlabToken())
            let jira = JiraClient(host: "jira.redge.com", token: try creds.jiraToken())
            let store = StatusStore(gitlabClient: gitlab, jiraClient: jira)
            self.store = store

            controller.onRefresh = { [weak store] in store?.refreshNow() }
            store.onUpdate = { [weak self, weak store] in
                guard let self, let store else { return }
                self.controller.update(gitlab: store.gitlab, jira: store.jira, lastRefresh: store.lastRefresh)
            }
            store.start()
        } catch {
            controller.showError(StatusStore.message(error))
        }
    }
}
```

- [ ] **Step 3: Write the entry point**

Replace `Sources/MRJiraMenuBar/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Compiling ...` then `Build complete!` with no errors.

- [ ] **Step 5: Manual verification**

Run: `swift run MRJiraMenuBar`
Expected, in the macOS menu bar:
- A status item showing four SF Symbols each followed by a number (a merge symbol + count, a seal + count, a tray + count, a bolt + count). Counts should match the live data (at spec-writing time: MR 8, ready unknown, backlog unknown, in progress 3).
- Hovering the item shows a tooltip like `Moje MR: 8 otwartych, … · Jira: … · odświeżono HH:mm`.
- Clicking opens the dropdown with GitLab and Jira sections; clicking a row opens the corresponding URL in the default browser.
- "Odśwież teraz" re-fetches; "Zakończ" exits.
- No Dock icon appears (agent app).

Stop with Ctrl-C in the terminal (or "Zakończ" in the menu).

- [ ] **Step 6: Commit**

```bash
git add Sources/MRJiraMenuBar
git commit -m "feat: NSStatusItem menu bar app wiring"
```

---

## Self-Review

**Spec coverage:**
- 4 counters → Tasks 2 (open MR), 3 (ready≥2), 4 (Jira backlog + in progress). ✓
- Definitions (ready=≥2 approvals; backlog=To Do/Backlog; in progress) → Task 3 threshold, Task 4 JQL constants. ✓
- AppKit `NSStatusItem` + SF Symbols + tooltip → Tasks 6 (formatter) + 7 (controller). ✓
- Tokens from glab yaml + jira file, in memory → Task 1. ✓
- Concurrent fetch, error isolation, last-known retention → Task 5. ✓
- Error handling (⚠ symbol, error rows, missing token instruction) → Task 5 (`message`) + Task 7 (`showError`, error rows). ✓
- Links to MR dashboard + Jira JQL filters → Task 7. ✓
- 5-min interval, agent app, no Keychain/settings (non-goals) → Task 5 default 300, Task 7 `.accessory`. ✓
- Testing plan (Credentials, GitLab, Jira, StatusStore, formatter) → Tasks 1–6. ✓

**Placeholder scan:** Task 2 intentionally ships a temporary `fetchReadyToMergeCount` returning 0, replaced in Task 3 (called out explicitly). No other placeholders.

**Type consistency:** `GitLabFetching`/`JiraFetching` protocols defined in Tasks 2/4, consumed in Task 5. `SourceResult`, `GitLabCounts`, `JiraCounts`, `TitleSegment` defined in Tasks 5/6, consumed in Task 7. `StatusFormatter.segments`/`tooltip` signatures match between Task 6 and Task 7. `JiraClient.backlogJQL`/`inProgressJQL` defined in Task 4, used in Task 7. Consistent.
