import XCTest
@testable import MenuBarCore

final class StatusFormatterTests: XCTestCase {
    func testSegmentsShowFourCountsInOrder() {
        let segs = StatusFormatter.segments(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 3))
        )
        XCTAssertEqual(segs.map(\.text), ["8", "2", "4", "3", "0", "0"])
        XCTAssertEqual(segs.map(\.symbol), [
            StatusFormatter.mrSymbol,
            StatusFormatter.readySymbol,
            StatusFormatter.backlogSymbol,
            StatusFormatter.inProgressSymbol,
            StatusFormatter.testingAwaitingSymbol,
            StatusFormatter.testingMovedOnSymbol,
        ])
    }

    func testSegmentsIncludeTestingCounts() {
        let segs = StatusFormatter.segments(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 3, testingAwaiting: 5, testingMovedOn: 11))
        )
        XCTAssertEqual(segs.map(\.text), ["8", "2", "4", "3", "5", "11"])
        XCTAssertEqual(segs[4].symbol, StatusFormatter.testingAwaitingSymbol)
        XCTAssertEqual(segs[5].symbol, StatusFormatter.testingMovedOnSymbol)
    }

    func testTooltipMentionsTestingCounts() {
        let tip = StatusFormatter.tooltip(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 3, testingAwaiting: 5, testingMovedOn: 11)),
            lastRefresh: nil
        )
        XCTAssertTrue(tip.contains("Testy: 5 czeka, 11 przetestowane"))
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

    func testTooltipShowsRetainedValueAndErrorTogether() {
        let tip = StatusFormatter.tooltip(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2), error: "boom"),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 3)),
            lastRefresh: nil
        )
        XCTAssertTrue(tip.contains("Moje MR: 8 otwartych, 2 gotowe do mergu (≥2 approve)"))
        XCTAssertTrue(tip.contains("GitLab błąd: boom"))
    }

    func testTooltipShowsErrorBranchesWhenNoValue() {
        let tip = StatusFormatter.tooltip(
            gitlab: SourceResult(value: nil, error: "gl-boom"),
            jira: SourceResult(value: nil, error: "jira-boom"),
            lastRefresh: nil
        )
        XCTAssertTrue(tip.contains("GitLab błąd: gl-boom"))
        XCTAssertTrue(tip.contains("Jira błąd: jira-boom"))
    }

    func testTooltipIncludesLastRefresh() {
        let tip = StatusFormatter.tooltip(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 3)),
            lastRefresh: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(tip.contains("odświeżono "))
    }

    func testSegmentsShowWarningSymbolForErroredSourceWithRetainedValue() {
        let segs = StatusFormatter.segments(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2), error: "boom"),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 3))
        )
        XCTAssertTrue(segs[0].isError)
        XCTAssertTrue(segs[1].isError)
        XCTAssertEqual(segs[0].symbol, StatusFormatter.errorSymbol)
        XCTAssertEqual(segs[1].symbol, StatusFormatter.errorSymbol)
        XCTAssertEqual(segs[0].text, "8")
        XCTAssertFalse(segs[2].isError)
        XCTAssertEqual(segs[2].symbol, StatusFormatter.backlogSymbol)
        XCTAssertEqual(segs[2].text, "4")
    }

    func testSegmentsShowLoadingEllipsisWhenNoValueAndNoError() {
        let segs = StatusFormatter.segments(
            gitlab: SourceResult(value: nil, error: nil),
            jira: SourceResult(value: nil, error: nil)
        )
        XCTAssertEqual(segs[0].text, "…")
        XCTAssertFalse(segs[0].isError)
        XCTAssertEqual(segs[0].symbol, StatusFormatter.mrSymbol)
    }

    func testSegmentsIncludeGitHubWhenVisible() {
        let segs = StatusFormatter.segments(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            github: SourceResult(value: GitHubCounts(open: 5, approved: 3)),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 1)),
            visibility: SourceVisibility(gitlab: true, github: true, jira: true)
        )
        XCTAssertEqual(segs.map(\.text), ["8", "2", "5", "3", "4", "1", "0", "0"])
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
        XCTAssertEqual(segs.map(\.text), ["8", "2", "4", "1", "0", "0"])
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

    func testSegmentsShowWarningSymbolForErroredGitHubWithRetainedValue() {
        let segs = StatusFormatter.segments(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            github: SourceResult(value: GitHubCounts(open: 5, approved: 3), error: "boom"),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 1)),
            visibility: SourceVisibility(gitlab: true, github: true, jira: true)
        )
        XCTAssertTrue(segs[2].isError)
        XCTAssertTrue(segs[3].isError)
        XCTAssertEqual(segs[2].symbol, StatusFormatter.errorSymbol)
        XCTAssertEqual(segs[3].symbol, StatusFormatter.errorSymbol)
        XCTAssertEqual(segs[2].text, "5")
        XCTAssertEqual(segs[3].text, "3")
        XCTAssertFalse(segs[0].isError)
        XCTAssertFalse(segs[4].isError)
    }

    func testTooltipShowsRetainedGitHubValueAndErrorTogether() {
        let tip = StatusFormatter.tooltip(
            gitlab: SourceResult(value: GitLabCounts(open: 8, ready: 2)),
            github: SourceResult(value: GitHubCounts(open: 5, approved: 3), error: "boom"),
            jira: SourceResult(value: JiraCounts(backlog: 4, inProgress: 1)),
            lastRefresh: nil,
            visibility: SourceVisibility(gitlab: true, github: true, jira: true)
        )
        XCTAssertTrue(tip.contains("GitHub: 5 PR, 3 approved"))
        XCTAssertTrue(tip.contains("GitHub błąd: boom"))
    }
}
