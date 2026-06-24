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
