import XCTest
@testable import MenuBarCore

private final class MutableGitLab: GitLabFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _open: Result<Int, Error>
    private var _ready: Result<Int, Error>

    var open: Result<Int, Error> {
        get { lock.withLock { _open } }
        set { lock.withLock { _open = newValue } }
    }
    var ready: Result<Int, Error> {
        get { lock.withLock { _ready } }
        set { lock.withLock { _ready = newValue } }
    }

    init(open: Result<Int, Error>, ready: Result<Int, Error>) { self._open = open; self._ready = ready }
    func fetchOpenMRCount() async throws -> Int { try open.get() }
    func fetchReadyToMergeCount() async throws -> Int { try ready.get() }
}

private final class MutableJira: JiraFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _backlog: Result<Int, Error>
    private var _inProgress: Result<Int, Error>

    var backlog: Result<Int, Error> {
        get { lock.withLock { _backlog } }
        set { lock.withLock { _backlog = newValue } }
    }
    var inProgress: Result<Int, Error> {
        get { lock.withLock { _inProgress } }
        set { lock.withLock { _inProgress = newValue } }
    }

    init(backlog: Result<Int, Error>, inProgress: Result<Int, Error>) {
        self._backlog = backlog
        self._inProgress = inProgress
    }
    func backlogCount() async throws -> Int { try backlog.get() }
    func inProgressCount() async throws -> Int { try inProgress.get() }
    func testingAwaitingCount() async throws -> Int { 0 }
    func testingAcceptedCount() async throws -> Int { 0 }
    func testingRejectedCount() async throws -> Int { 0 }
}

private struct FakeGitHub: GitHubFetching {
    var open: Result<Int, Error>
    var approved: Result<Int, Error>
    func fetchOpenPRCount() async throws -> Int { try open.get() }
    func fetchApprovedPRCount() async throws -> Int { try approved.get() }
}

private final class MutableGitHub: GitHubFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _open: Result<Int, Error>
    private var _approved: Result<Int, Error>

    var open: Result<Int, Error> {
        get { lock.withLock { _open } }
        set { lock.withLock { _open = newValue } }
    }
    var approved: Result<Int, Error> {
        get { lock.withLock { _approved } }
        set { lock.withLock { _approved = newValue } }
    }

    init(open: Result<Int, Error>, approved: Result<Int, Error>) { self._open = open; self._approved = approved }
    func fetchOpenPRCount() async throws -> Int { try open.get() }
    func fetchApprovedPRCount() async throws -> Int { try approved.get() }
}

private enum TestError: Error { case boom }

private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }

        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private final class GatedGitLab: GitLabFetching, @unchecked Sendable {
    let gate: Gate
    let value: Int
    init(gate: Gate, value: Int) { self.gate = gate; self.value = value }
    func fetchOpenMRCount() async throws -> Int { await gate.wait(); return value }
    func fetchReadyToMergeCount() async throws -> Int { await gate.wait(); return value }
}

final class StatusStoreTests: XCTestCase {
    @MainActor
    func testSuccessPopulatesBothSources() async {
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(8), ready: .success(2)),
            jiraClient: MutableJira(backlog: .success(4), inProgress: .success(3))
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
            jiraClient: MutableJira(backlog: .success(4), inProgress: .success(3))
        )
        await store.refresh()
        gl.open = .failure(TestError.boom)
        await store.refresh()
        XCTAssertEqual(store.gitlab.value, GitLabCounts(open: 8, ready: 2))
        XCTAssertNotNil(store.gitlab.error)
        XCTAssertEqual(store.jira.value, JiraCounts(backlog: 4, inProgress: 3))
        XCTAssertNil(store.jira.error)
    }

    @MainActor
    func testJiraErrorRetainsLastValueAndLeavesGitLabIntact() async {
        let jira = MutableJira(backlog: .success(4), inProgress: .success(3))
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(8), ready: .success(2)),
            jiraClient: jira
        )
        await store.refresh()
        jira.backlog = .failure(TestError.boom)
        await store.refresh()
        XCTAssertEqual(store.jira.value, JiraCounts(backlog: 4, inProgress: 3))
        XCTAssertNotNil(store.jira.error)
        XCTAssertEqual(store.gitlab.value, GitLabCounts(open: 8, ready: 2))
        XCTAssertNil(store.gitlab.error)
    }

    @MainActor
    func testRefreshNotifiesViaOnUpdate() async {
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(8), ready: .success(2)),
            jiraClient: MutableJira(backlog: .success(4), inProgress: .success(3))
        )
        var updates = 0
        store.onUpdate = { updates += 1 }
        await store.refresh()
        XCTAssertGreaterThanOrEqual(updates, 1)
    }

    @MainActor
    func testSetClientsSwapsSourcesForNextRefresh() async {
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(1), ready: .success(0)),
            jiraClient: MutableJira(backlog: .success(0), inProgress: .success(0))
        )
        await store.refresh()
        XCTAssertEqual(store.gitlab.value, GitLabCounts(open: 1, ready: 0))

        store.setClients(
            gitlabClient: MutableGitLab(open: .success(9), ready: .success(4)),
            jiraClient: MutableJira(backlog: .success(2), inProgress: .success(1))
        )
        await store.refresh()
        XCTAssertEqual(store.gitlab.value, GitLabCounts(open: 9, ready: 4))
        XCTAssertEqual(store.jira.value, JiraCounts(backlog: 2, inProgress: 1))
    }

    @MainActor
    func testRestartRefreshAppliesSwappedClientsWhileRefreshInFlight() async {
        let staleGate = Gate()
        let store = StatusStore(
            gitlabClient: GatedGitLab(gate: staleGate, value: 1),
            jiraClient: MutableJira(backlog: .success(0), inProgress: .success(0))
        )

        store.refreshNow()
        XCTAssertNil(store.gitlab.value)

        let freshGate = Gate()
        await freshGate.open()
        store.setClients(
            gitlabClient: GatedGitLab(gate: freshGate, value: 9),
            jiraClient: MutableJira(backlog: .success(2), inProgress: .success(1))
        )
        store.restartRefresh()

        await staleGate.open()

        for _ in 0..<200 {
            if store.gitlab.value == GitLabCounts(open: 9, ready: 9) { break }

            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(store.gitlab.value, GitLabCounts(open: 9, ready: 9))
        XCTAssertEqual(store.jira.value, JiraCounts(backlog: 2, inProgress: 1))
    }

    @MainActor
    func testGitHubSourcePopulatesWhenClientPresent() async {
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(1), ready: .success(0)),
            jiraClient: MutableJira(backlog: .success(0), inProgress: .success(0)),
            githubClient: FakeGitHub(open: .success(5), approved: .success(3))
        )
        await store.refresh()
        XCTAssertEqual(store.github.value, GitHubCounts(open: 5, approved: 3))
    }

    @MainActor
    func testGitHubClearsToNeutralWhenClientNil() async {
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(1), ready: .success(0)),
            jiraClient: MutableJira(backlog: .success(0), inProgress: .success(0)),
            githubClient: FakeGitHub(open: .success(5), approved: .success(3))
        )
        await store.refresh()
        XCTAssertNotNil(store.github.value)

        store.setClients(
            gitlabClient: MutableGitLab(open: .success(1), ready: .success(0)),
            jiraClient: MutableJira(backlog: .success(0), inProgress: .success(0)),
            githubClient: nil
        )
        await store.refresh()
        XCTAssertNil(store.github.value)
        XCTAssertNil(store.github.error)
    }

    @MainActor
    func testGitHubErrorRetainsLastValueAndLeavesGitLabJiraIntact() async {
        let gh = MutableGitHub(open: .success(5), approved: .success(3))
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(8), ready: .success(2)),
            jiraClient: MutableJira(backlog: .success(4), inProgress: .success(1)),
            githubClient: gh
        )
        await store.refresh()
        gh.open = .failure(TestError.boom)
        await store.refresh()
        XCTAssertEqual(store.github.value, GitHubCounts(open: 5, approved: 3))
        XCTAssertNotNil(store.github.error)
        XCTAssertEqual(store.gitlab.value, GitLabCounts(open: 8, ready: 2))
        XCTAssertNil(store.gitlab.error)
        XCTAssertEqual(store.jira.value, JiraCounts(backlog: 4, inProgress: 1))
        XCTAssertNil(store.jira.error)
    }

    @MainActor
    func testGitLabClearsToNeutralWhenClientNilAndLeavesOthersIntact() async {
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(8), ready: .success(2)),
            jiraClient: MutableJira(backlog: .success(4), inProgress: .success(1))
        )
        await store.refresh()
        XCTAssertNotNil(store.gitlab.value)

        store.setClients(
            gitlabClient: nil,
            jiraClient: MutableJira(backlog: .success(4), inProgress: .success(1))
        )
        await store.refresh()
        XCTAssertNil(store.gitlab.value)
        XCTAssertNil(store.gitlab.error)
        XCTAssertEqual(store.jira.value, JiraCounts(backlog: 4, inProgress: 1))
    }

    @MainActor
    func testJiraClearsToNeutralWhenClientNilAndLeavesOthersIntact() async {
        let store = StatusStore(
            gitlabClient: MutableGitLab(open: .success(8), ready: .success(2)),
            jiraClient: MutableJira(backlog: .success(4), inProgress: .success(1))
        )
        await store.refresh()
        XCTAssertNotNil(store.jira.value)

        store.setClients(
            gitlabClient: MutableGitLab(open: .success(8), ready: .success(2)),
            jiraClient: nil
        )
        await store.refresh()
        XCTAssertNil(store.jira.value)
        XCTAssertNil(store.jira.error)
        XCTAssertEqual(store.gitlab.value, GitLabCounts(open: 8, ready: 2))
    }

    @MainActor
    func testInactiveSourcesAreNotFetched() async {
        let store = StatusStore(gitlabClient: nil, jiraClient: nil, githubClient: nil)
        await store.refresh()
        XCTAssertNil(store.gitlab.value)
        XCTAssertNil(store.gitlab.error)
        XCTAssertNil(store.jira.value)
        XCTAssertNil(store.jira.error)
        XCTAssertNil(store.github.value)
        XCTAssertNil(store.github.error)
        XCTAssertNotNil(store.lastRefresh)
    }
}
