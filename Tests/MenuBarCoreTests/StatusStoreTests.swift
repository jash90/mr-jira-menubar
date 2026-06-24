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
}

private enum TestError: Error { case boom }

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
}
