# Sticky "Rejected" Counter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The "Odrzucone" counter permanently counts every issue the user ever had bounced from `Internal testing` back to `In Progress` by someone else, verified by the user's own GitLab MR.

**Architecture:** `JiraClient` learns to return issue keys + dated transitions (paginated) and detect a rejection cycle from the changelog. `GitLabClient` learns to check for the user's MR referencing an issue key. A new `RejectedIssuesService` combines both with an in-memory verdict cache; `ClientFactory` wraps the Jira client in a thin `JiraFetching` adapter so `StatusStore` stays untouched.

**Tech Stack:** Swift 5.9 SPM package, Foundation-only core (`Sources/MenuBarCore`), XCTest with `StubURLProtocol`.

Spec: `docs/superpowers/specs/2026-07-14-sticky-rejected-counter-design.md`

## Global Constraints

- English for all commit messages and code identifiers; chat/UI copy stays Polish.
- Comments are a last resort — prefer self-documenting names; keep any comment ≤3 lines.
- Blank line before and after every `if` block (unless first/last statement in its block); never pad `{`/`}` with blank lines.
- All tests via `swift test` (package root `/Users/redge/Projects/mr-jira-menubar`).
- New candidate JQL (verbatim): `status CHANGED TO "Internal testing" BY currentUser() AND status CHANGED FROM "Internal testing" TO "In Progress"`
- Changelog date format (verbatim): `yyyy-MM-dd'T'HH:mm:ss.SSSZ` with locale `en_US_POSIX`; unparseable/missing dates fall back to `.distantFuture`.
- Fail-open rule: GitLab transport/HTTP errors never exclude an issue and are never cached; only a confirmed zero-result response excludes.

---

### Task 1: Dated, keyed, paginated changelog search in JiraClient

**Files:**
- Modify: `Sources/MenuBarCore/JiraClient.swift`
- Test: `Tests/MenuBarCoreTests/JiraClientTests.swift`

**Interfaces:**
- Produces: `StatusTransition.init(author: String, toStatus: String, date: Date = .distantPast)` (new `date` stored property), `struct IssueTransitions { let key: String; let transitions: [StatusTransition] }` (internal, memberwise init), `func searchTransitions(jql: String) async throws -> [IssueTransitions]` (internal, paginates with `startAt`), `JiraClient.changelogDateFormatter` (internal static).
- Consumes: existing `get(path:queryItems:)`, `ChangelogSearchResult` decoding.

- [ ] **Step 1: Write the failing tests**

In `Tests/MenuBarCoreTests/JiraClientTests.swift`, DELETE `testRejectedCountFiltersOutOtherDevelopersRounds` (its stub JSON lacks the now-required `key`/`total` fields and the rejected counter is rewritten in Task 2) and ADD in its place:

```swift
    func testSearchTransitionsPaginatesAndParsesKeysAndDates() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url!.path, "/rest/api/2/search")
            let query = req.url!.query!
            XCTAssertTrue(query.contains("expand=changelog"))
            let pageOne = #"""
                {"total":2,"issues":[
                {"key":"SOFKRS-1","changelog":{"histories":[
                {"author":{"name":"me"},"created":"2026-01-10T10:00:00.000+0100","items":[{"field":"status","toString":"Internal testing"}]}]}}]}
                """#
            let pageTwo = #"""
                {"total":2,"issues":[
                {"key":"SOFKRS-2","changelog":{"histories":[
                {"author":{"name":"tester"},"items":[{"field":"status","toString":"In Progress"}]}]}}]}
                """#
            let body = query.contains("startAt=0") ? pageOne : pageTwo
            return .init(statusCode: 200, body: Data(body.utf8))
        }
        let client = JiraClient(host: "jira.example", token: "tok", session: StubURLProtocol.session())
        let issues = try await client.searchTransitions(jql: "anything")
        XCTAssertEqual(issues.map(\.key), ["SOFKRS-1", "SOFKRS-2"])
        let expectedDate = JiraClient.changelogDateFormatter.date(from: "2026-01-10T10:00:00.000+0100")!
        XCTAssertEqual(issues[0].transitions, [StatusTransition(author: "me", toStatus: "Internal testing", date: expectedDate)])
        XCTAssertEqual(issues[1].transitions[0].date, .distantFuture)
    }

    func testAcceptedCountFiltersOutOtherDevelopersRounds() async throws {
        StubURLProtocol.handler = { req in
            if req.url!.path == "/rest/api/2/myself" {
                return .init(statusCode: 200, body: Data(#"{"name":"me"}"#.utf8))
            }

            XCTAssertEqual(req.url!.path, "/rest/api/2/search")
            let mine = #"""
                {"key":"SOFKRS-1","changelog":{"histories":[
                {"author":{"name":"me"},"items":[{"field":"status","toString":"Code review"}]},
                {"author":{"name":"reviewer"},"items":[{"field":"status","toString":"Internal testing"}]},
                {"author":{"name":"tester"},"items":[{"field":"status","toString":"Acceptance"}]}]}}
                """#
            let takenOver = #"""
                {"key":"SOFKRS-2","changelog":{"histories":[
                {"author":{"name":"other.dev"},"items":[{"field":"status","toString":"Code review"}]},
                {"author":{"name":"reviewer"},"items":[{"field":"status","toString":"Internal testing"}]},
                {"author":{"name":"tester"},"items":[{"field":"status","toString":"Acceptance"}]}]}}
                """#
            let body = #"{"total":2,"issues":["# + mine + "," + takenOver + "]}"
            return .init(statusCode: 200, body: Data(body.utf8))
        }
        let client = JiraClient(host: "jira.example", token: "tok", session: StubURLProtocol.session())
        let count = try await client.testingAcceptedCount()
        XCTAssertEqual(count, 1)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter JiraClientTests 2>&1 | tail -20`
Expected: compile FAILURE (`IssueTransitions` and `changelogDateFormatter` not defined; `StatusTransition` has no `date`).

- [ ] **Step 3: Implement in `Sources/MenuBarCore/JiraClient.swift`**

Replace `StatusTransition` with:

```swift
public struct StatusTransition: Equatable, Sendable {
    public let author: String
    public let toStatus: String
    public let date: Date

    public init(author: String, toStatus: String, date: Date = .distantPast) {
        self.author = author
        self.toStatus = toStatus
        self.date = date
    }
}
```

Below it add:

```swift
struct IssueTransitions: Equatable, Sendable {
    let key: String
    let transitions: [StatusTransition]
}
```

In `JiraClient`, replace `ChangelogSearchResult` with:

```swift
    struct ChangelogSearchResult: Decodable {
        let total: Int
        let issues: [Issue]

        struct Issue: Decodable { let key: String; let changelog: Changelog }
        struct Changelog: Decodable { let histories: [History] }
        struct History: Decodable { let author: Author; let created: String?; let items: [Item] }
        struct Author: Decodable { let name: String }
        struct Item: Decodable {
            let field: String
            let to: String?
            enum CodingKeys: String, CodingKey {
                case field
                case to = "toString"
            }
        }
    }

    static let changelogDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()
```

Replace `searchTransitions` with the paginated, key-returning version:

```swift
    func searchTransitions(jql: String) async throws -> [IssueTransitions] {
        var startAt = 0
        var result: [IssueTransitions] = []
        while true {
            let data = try await get(path: "/rest/api/2/search", queryItems: [
                .init(name: "jql", value: jql),
                .init(name: "expand", value: "changelog"),
                .init(name: "fields", value: "status"),
                .init(name: "maxResults", value: "100"),
                .init(name: "startAt", value: String(startAt)),
            ])
            let page = try JSONDecoder().decode(ChangelogSearchResult.self, from: data)
            result.append(contentsOf: page.issues.map(Self.issueTransitions(from:)))
            startAt += page.issues.count

            if page.issues.isEmpty || startAt >= page.total { break }
        }
        return result
    }

    static func issueTransitions(from issue: ChangelogSearchResult.Issue) -> IssueTransitions {
        let transitions = issue.changelog.histories.flatMap { history -> [StatusTransition] in
            let date = history.created.flatMap(changelogDateFormatter.date(from:)) ?? .distantFuture
            return history.items.compactMap { item -> StatusTransition? in
                guard item.field == "status", let to = item.to else { return nil }

                return StatusTransition(author: history.author.name, toStatus: to, date: date)
            }
        }
        return IssueTransitions(key: issue.key, transitions: transitions)
    }
```

Adapt `myDevelopedCount` to the new return type — change its filter line to:

```swift
        return try await transitionsPerIssue
            .filter { Self.developerOfLastTestingRound($0.transitions) == developer }
            .count
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter JiraClientTests 2>&1 | tail -5`
Expected: all JiraClientTests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarCore/JiraClient.swift Tests/MenuBarCoreTests/JiraClientTests.swift
git commit -m "feat: dated, keyed, paginated changelog search in JiraClient"
```

---

### Task 2: Rejection-cycle detection and the sticky rejected count

**Files:**
- Modify: `Sources/MenuBarCore/JiraClient.swift`
- Test: `Tests/MenuBarCoreTests/JiraClientTests.swift`

**Interfaces:**
- Consumes: `StatusTransition` (with `date`), `IssueTransitions`, `searchTransitions(jql:)`, `myself()` from Task 1.
- Produces: `JiraClient.everRejectedJQL` (public static let), `JiraClient.inProgressStatus` (public static let, value `"In Progress"`), `static func rejectionCycle(in transitions: [StatusTransition], me: String) -> Date?`, `func rejectionCandidates() async throws -> [IssueTransitions]` (internal), rewritten `testingRejectedCount()` (changelog-only). REMOVES `JiraClient.testingRejectedJQL`.

- [ ] **Step 1: Write the failing tests**

In `Tests/MenuBarCoreTests/JiraClientTests.swift`, DELETE `testTestingRejectedJQLMatchesSpec` and ADD:

```swift
    func testEverRejectedJQLMatchesSpec() {
        XCTAssertEqual(
            JiraClient.everRejectedJQL,
            #"status CHANGED TO "Internal testing" BY currentUser() AND status CHANGED FROM "Internal testing" TO "In Progress""#
        )
    }

    func testRejectionCycleDetectsBounceBySomeoneElse() {
        let bounceDate = Date(timeIntervalSince1970: 100)
        let transitions = [
            StatusTransition(author: "me", toStatus: "Internal testing", date: Date(timeIntervalSince1970: 50)),
            StatusTransition(author: "tester", toStatus: "In Progress", date: bounceDate),
        ]
        XCTAssertEqual(JiraClient.rejectionCycle(in: transitions, me: "me"), bounceDate)
    }

    // Sticky: the cycle counts even when the issue later went to testing again and got accepted.
    func testRejectionCycleSurvivesLaterAcceptance() {
        let bounceDate = Date(timeIntervalSince1970: 100)
        let transitions = [
            StatusTransition(author: "me", toStatus: "Internal testing", date: Date(timeIntervalSince1970: 50)),
            StatusTransition(author: "tester", toStatus: "In Progress", date: bounceDate),
            StatusTransition(author: "me", toStatus: "Internal testing", date: Date(timeIntervalSince1970: 200)),
            StatusTransition(author: "tester", toStatus: "Acceptance", date: Date(timeIntervalSince1970: 300)),
        ]
        XCTAssertEqual(JiraClient.rejectionCycle(in: transitions, me: "me"), bounceDate)
    }

    func testRejectionCycleIgnoresBounceByMe() {
        let transitions = [
            StatusTransition(author: "me", toStatus: "Internal testing"),
            StatusTransition(author: "me", toStatus: "In Progress"),
        ]
        XCTAssertNil(JiraClient.rejectionCycle(in: transitions, me: "me"))
    }

    func testRejectionCycleIgnoresBounceToOtherStatus() {
        let transitions = [
            StatusTransition(author: "me", toStatus: "Internal testing"),
            StatusTransition(author: "tester", toStatus: "Code review"),
        ]
        XCTAssertNil(JiraClient.rejectionCycle(in: transitions, me: "me"))
    }

    func testRejectionCycleIgnoresOtherDevelopersCycle() {
        let transitions = [
            StatusTransition(author: "other.dev", toStatus: "Internal testing"),
            StatusTransition(author: "tester", toStatus: "In Progress"),
        ]
        XCTAssertNil(JiraClient.rejectionCycle(in: transitions, me: "me"))
    }

    func testRejectionCycleNilWithoutBounce() {
        let transitions = [
            StatusTransition(author: "me", toStatus: "Internal testing"),
        ]
        XCTAssertNil(JiraClient.rejectionCycle(in: transitions, me: "me"))
    }

    func testRejectedCountCountsCyclesFromChangelog() async throws {
        StubURLProtocol.handler = { req in
            if req.url!.path == "/rest/api/2/myself" {
                return .init(statusCode: 200, body: Data(#"{"name":"me"}"#.utf8))
            }

            let rejected = #"""
                {"key":"SOFKRS-1","changelog":{"histories":[
                {"author":{"name":"me"},"items":[{"field":"status","toString":"Internal testing"}]},
                {"author":{"name":"tester"},"items":[{"field":"status","toString":"In Progress"}]}]}}
                """#
            let selfBounced = #"""
                {"key":"SOFKRS-2","changelog":{"histories":[
                {"author":{"name":"me"},"items":[{"field":"status","toString":"Internal testing"}]},
                {"author":{"name":"me"},"items":[{"field":"status","toString":"In Progress"}]}]}}
                """#
            let body = #"{"total":2,"issues":["# + rejected + "," + selfBounced + "]}"
            return .init(statusCode: 200, body: Data(body.utf8))
        }
        let client = JiraClient(host: "jira.example", token: "tok", session: StubURLProtocol.session())
        let count = try await client.testingRejectedCount()
        XCTAssertEqual(count, 1)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter JiraClientTests 2>&1 | tail -20`
Expected: compile FAILURE (`everRejectedJQL`, `rejectionCycle` not defined).

- [ ] **Step 3: Implement in `Sources/MenuBarCore/JiraClient.swift`**

DELETE the `testingRejectedJQL` constant (lines with `public static let testingRejectedJQL`). Keep `preTestingStatuses` (still used by `testingAcceptedJQL`).

Next to the other status constants add:

```swift
    public static let inProgressStatus = "In Progress"
    public static let everRejectedJQL =
        #"status CHANGED TO "Internal testing" BY currentUser() AND status CHANGED FROM "Internal testing" TO "In Progress""#
```

Below `developerOfLastTestingRound` add:

```swift
    // A rejection: I sent the issue to testing and the very next status change is
    // someone else bouncing it back to In Progress. Returns the bounce date.
    public static func rejectionCycle(in transitions: [StatusTransition], me: String) -> Date? {
        for (index, transition) in transitions.enumerated() {
            guard transition.toStatus == testingStatus, transition.author == me else { continue }

            let next = transitions[(index + 1)...].first

            if let next, next.toStatus == inProgressStatus, next.author != me {
                return next.date
            }
        }

        return nil
    }

    func rejectionCandidates() async throws -> [IssueTransitions] {
        try await searchTransitions(jql: Self.everRejectedJQL)
    }
```

Replace the `testingRejectedCount()` body:

```swift
    public func testingRejectedCount() async throws -> Int {
        async let me = myself()
        async let candidates = rejectionCandidates()
        let developer = try await me
        return try await candidates
            .filter { Self.rejectionCycle(in: $0.transitions, me: developer) != nil }
            .count
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter JiraClientTests 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarCore/JiraClient.swift Tests/MenuBarCoreTests/JiraClientTests.swift
git commit -m "feat: sticky rejected count from changelog rejection cycles"
```

---

### Task 3: GitLab MR lookup by issue key

**Files:**
- Modify: `Sources/MenuBarCore/GitLabClient.swift`
- Test: `Tests/MenuBarCoreTests/GitLabClientTests.swift`

**Interfaces:**
- Consumes: existing `request(_:query:)`, `GitLabError`.
- Produces: `protocol MergeRequestLookup: Sendable { func hasMyMergeRequest(referencing key: String, createdBefore: Date) async throws -> Bool }` and `GitLabClient: MergeRequestLookup` conformance.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/MenuBarCoreTests/GitLabClientTests.swift` (inside the test class; it already stubs via `StubURLProtocol` — mirror the surrounding style):

```swift
    func testHasMyMergeRequestSendsSearchQueryAndReadsTotal() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url!.path, "/api/v4/merge_requests")
            let query = req.url!.query!
            XCTAssertTrue(query.contains("scope=created_by_me"))
            XCTAssertTrue(query.contains("state=all"))
            XCTAssertTrue(query.contains("search=SOFKRS-1234"))
            XCTAssertTrue(query.contains("created_before=2026-01-10"))
            return .init(statusCode: 200, headers: ["X-Total": "1"], body: Data("[]".utf8))
        }
        let client = GitLabClient(host: "gl.example", token: "tok", session: StubURLProtocol.session())
        let cutoff = JiraClient.changelogDateFormatter.date(from: "2026-01-10T10:00:00.000+0000")!
        let found = try await client.hasMyMergeRequest(referencing: "SOFKRS-1234", createdBefore: cutoff)
        XCTAssertTrue(found)
    }

    func testHasMyMergeRequestIsFalseOnZeroTotal() async throws {
        StubURLProtocol.handler = { _ in .init(statusCode: 200, headers: ["X-Total": "0"], body: Data("[]".utf8)) }
        let client = GitLabClient(host: "gl.example", token: "tok", session: StubURLProtocol.session())
        let found = try await client.hasMyMergeRequest(referencing: "SOFKRS-1", createdBefore: .distantFuture)
        XCTAssertFalse(found)
    }

    func testHasMyMergeRequestThrowsOnHTTPError() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 500) }
        let client = GitLabClient(host: "gl.example", token: "tok", session: StubURLProtocol.session())
        do {
            _ = try await client.hasMyMergeRequest(referencing: "SOFKRS-1", createdBefore: .distantFuture)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? GitLabError, .status(500))
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GitLabClientTests 2>&1 | tail -20`
Expected: compile FAILURE (`hasMyMergeRequest` not defined).

- [ ] **Step 3: Implement in `Sources/MenuBarCore/GitLabClient.swift`**

Below the `GitLabFetching` protocol add:

```swift
public protocol MergeRequestLookup: Sendable {
    func hasMyMergeRequest(referencing key: String, createdBefore: Date) async throws -> Bool
}
```

Change the `GitLabClient` declaration to `public struct GitLabClient: GitLabFetching, MergeRequestLookup, Sendable {` and add inside:

```swift
    static let createdBeforeFormatter = ISO8601DateFormatter()

    public func hasMyMergeRequest(referencing key: String, createdBefore: Date) async throws -> Bool {
        let req = request("/merge_requests", query: [
            .init(name: "scope", value: "created_by_me"),
            .init(name: "state", value: "all"),
            .init(name: "search", value: key),
            .init(name: "created_before", value: Self.createdBeforeFormatter.string(from: createdBefore)),
            .init(name: "per_page", value: "1"),
        ])
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GitLabError.badResponse }
        guard http.statusCode == 200 else { throw GitLabError.status(http.statusCode) }
        guard let total = http.value(forHTTPHeaderField: "X-Total"), let n = Int(total) else {
            throw GitLabError.missingTotal
        }
        return n > 0
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GitLabClientTests 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarCore/GitLabClient.swift Tests/MenuBarCoreTests/GitLabClientTests.swift
git commit -m "feat: GitLab lookup for my MRs referencing an issue key"
```

---

### Task 4: RejectedIssuesService with verdict cache and fail-open

**Files:**
- Create: `Sources/MenuBarCore/RejectedIssuesService.swift`
- Test: `Tests/MenuBarCoreTests/RejectedIssuesServiceTests.swift`

**Interfaces:**
- Consumes: `MergeRequestLookup` (Task 3), `IssueTransitions`, `JiraClient.rejectionCycle(in:me:)`, `JiraFetching`.
- Produces: `protocol RejectionCandidateFetching: Sendable { func myself() async throws -> String; func rejectionCandidates() async throws -> [IssueTransitions] }` (internal; `JiraClient` conformance declared here), `actor RejectedIssuesService { init(jira:gitlab:); func rejectedCount() async throws -> Int }` (internal), `struct JiraWithRejectionService: JiraFetching` (internal, `init(base: JiraClient, service: RejectedIssuesService)` memberwise).

- [ ] **Step 1: Write the failing tests**

Create `Tests/MenuBarCoreTests/RejectedIssuesServiceTests.swift`:

```swift
import XCTest
@testable import MenuBarCore

private struct StubJira: RejectionCandidateFetching {
    let me: String
    let candidates: [IssueTransitions]
    func myself() async throws -> String { me }
    func rejectionCandidates() async throws -> [IssueTransitions] { candidates }
}

private final class StubMRLookup: MergeRequestLookup, @unchecked Sendable {
    var verdict: Result<Bool, Error>
    private(set) var calls: [String] = []

    init(verdict: Result<Bool, Error>) { self.verdict = verdict }

    func hasMyMergeRequest(referencing key: String, createdBefore: Date) async throws -> Bool {
        calls.append(key)
        return try verdict.get()
    }
}

final class RejectedIssuesServiceTests: XCTestCase {
    private let rejectedIssue = IssueTransitions(key: "SOFKRS-1", transitions: [
        StatusTransition(author: "me", toStatus: "Internal testing", date: Date(timeIntervalSince1970: 50)),
        StatusTransition(author: "tester", toStatus: "In Progress", date: Date(timeIntervalSince1970: 100)),
    ])
    private let cleanIssue = IssueTransitions(key: "SOFKRS-2", transitions: [
        StatusTransition(author: "me", toStatus: "Internal testing", date: Date(timeIntervalSince1970: 50)),
    ])

    func testCountsCycleIssuesVerifiedByGitLab() async throws {
        let gitlab = StubMRLookup(verdict: .success(true))
        let service = RejectedIssuesService(
            jira: StubJira(me: "me", candidates: [rejectedIssue, cleanIssue]),
            gitlab: gitlab)
        let count = try await service.rejectedCount()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(gitlab.calls, ["SOFKRS-1"])
    }

    func testExcludesIssueWhenGitLabConfirmsNoMR() async throws {
        let service = RejectedIssuesService(
            jira: StubJira(me: "me", candidates: [rejectedIssue]),
            gitlab: StubMRLookup(verdict: .success(false)))
        let count = try await service.rejectedCount()
        XCTAssertEqual(count, 0)
    }

    func testCachesVerdictAcrossRefreshes() async throws {
        let gitlab = StubMRLookup(verdict: .success(true))
        let service = RejectedIssuesService(
            jira: StubJira(me: "me", candidates: [rejectedIssue]),
            gitlab: gitlab)
        _ = try await service.rejectedCount()
        _ = try await service.rejectedCount()
        XCTAssertEqual(gitlab.calls, ["SOFKRS-1"])
    }

    func testGitLabErrorFailsOpenAndIsNotCached() async throws {
        let gitlab = StubMRLookup(verdict: .failure(GitLabError.status(500)))
        let service = RejectedIssuesService(
            jira: StubJira(me: "me", candidates: [rejectedIssue]),
            gitlab: gitlab)
        let count = try await service.rejectedCount()
        XCTAssertEqual(count, 1)

        gitlab.verdict = .success(false)
        let retried = try await service.rejectedCount()
        XCTAssertEqual(retried, 0)
        XCTAssertEqual(gitlab.calls, ["SOFKRS-1", "SOFKRS-1"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RejectedIssuesServiceTests 2>&1 | tail -20`
Expected: compile FAILURE (`RejectionCandidateFetching`, `RejectedIssuesService` not defined).

- [ ] **Step 3: Create `Sources/MenuBarCore/RejectedIssuesService.swift`**

```swift
import Foundation

protocol RejectionCandidateFetching: Sendable {
    func myself() async throws -> String
    func rejectionCandidates() async throws -> [IssueTransitions]
}

extension JiraClient: RejectionCandidateFetching {}

actor RejectedIssuesService {
    private let jira: any RejectionCandidateFetching
    private let gitlab: any MergeRequestLookup
    private var verdicts: [String: Bool] = [:]

    init(jira: any RejectionCandidateFetching, gitlab: any MergeRequestLookup) {
        self.jira = jira
        self.gitlab = gitlab
    }

    func rejectedCount() async throws -> Int {
        let me = try await jira.myself()
        let candidates = try await jira.rejectionCandidates()
        var count = 0

        for candidate in candidates {
            guard let bouncedAt = JiraClient.rejectionCycle(in: candidate.transitions, me: me) else { continue }

            if await hasVerifiedMR(key: candidate.key, before: bouncedAt) { count += 1 }
        }

        return count
    }

    // Fail-open: a GitLab error never excludes an issue and is never cached,
    // so the next refresh retries; only confirmed verdicts persist.
    private func hasVerifiedMR(key: String, before bouncedAt: Date) async -> Bool {
        if let cached = verdicts[key] { return cached }

        guard let verdict = try? await gitlab.hasMyMergeRequest(referencing: key, createdBefore: bouncedAt) else { return true }

        verdicts[key] = verdict
        return verdict
    }
}

struct JiraWithRejectionService: JiraFetching {
    let base: JiraClient
    let service: RejectedIssuesService

    func backlogCount() async throws -> Int { try await base.backlogCount() }
    func inProgressCount() async throws -> Int { try await base.inProgressCount() }
    func testingAwaitingCount() async throws -> Int { try await base.testingAwaitingCount() }
    func testingAcceptedCount() async throws -> Int { try await base.testingAcceptedCount() }
    func testingRejectedCount() async throws -> Int { try await service.rejectedCount() }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RejectedIssuesServiceTests 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarCore/RejectedIssuesService.swift Tests/MenuBarCoreTests/RejectedIssuesServiceTests.swift
git commit -m "feat: RejectedIssuesService combining Jira cycles with GitLab MR proof"
```

---

### Task 5: Wire the service via ClientFactory and update the menu link

**Files:**
- Modify: `Sources/MenuBarCore/ClientFactory.swift`
- Modify: `Sources/MRJiraMenuBar/StatusItemController.swift:166`
- Test: `Tests/MenuBarCoreTests/ClientFactoryTests.swift`

**Interfaces:**
- Consumes: `RejectedIssuesService`, `JiraWithRejectionService` (Task 4), `JiraClient.everRejectedJQL` (Task 2).
- Produces: `ClientFactory.makeJira` returns `JiraWithRejectionService` when both Jira and GitLab are active, plain `JiraClient` when only Jira is.

- [ ] **Step 1: Write the failing test**

Append to `Tests/MenuBarCoreTests/ClientFactoryTests.swift`:

```swift
    func testMakeJiraWrapsWithRejectionServiceWhenGitLabActive() {
        let both = AppConfig(
            gitlabHost: "gl.example",
            gitlabToken: "gt",
            jiraHost: "jira.example",
            jiraToken: "jt"
        )
        XCTAssertTrue(ClientFactory.makeJira(both) is JiraWithRejectionService)

        let jiraOnly = AppConfig(jiraHost: "jira.example", jiraToken: "jt")
        XCTAssertTrue(ClientFactory.makeJira(jiraOnly) is JiraClient)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClientFactoryTests 2>&1 | tail -10`
Expected: FAIL (`makeJira` returns plain `JiraClient` for the `both` config).

- [ ] **Step 3: Implement**

In `Sources/MenuBarCore/ClientFactory.swift` replace `makeJira` with:

```swift
    public static func makeJira(_ config: AppConfig) -> (any JiraFetching)? {
        guard config.jiraActive else { return nil }

        let jira = JiraClient(host: config.jiraHost, token: config.jiraToken)

        guard config.gitlabActive else { return jira }

        let gitlab = GitLabClient(host: config.gitlabHost, token: config.gitlabToken)
        return JiraWithRejectionService(base: jira, service: RejectedIssuesService(jira: jira, gitlab: gitlab))
    }
```

In `Sources/MRJiraMenuBar/StatusItemController.swift` line 166, change the rejected row link:

```swift
            menu.addItem(link("  Odrzucone: \(rejectedText)", url: jiraURL(JiraClient.everRejectedJQL)))
```

- [ ] **Step 4: Run the full suite and build**

Run: `swift test 2>&1 | tail -5`
Expected: all tests PASS.

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!` (compiles the AppKit target too, catching the menu-link change).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarCore/ClientFactory.swift Sources/MRJiraMenuBar/StatusItemController.swift Tests/MenuBarCoreTests/ClientFactoryTests.swift
git commit -m "feat: wire sticky rejected counter through ClientFactory and menu link"
```
