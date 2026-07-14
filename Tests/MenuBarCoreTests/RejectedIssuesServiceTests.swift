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
