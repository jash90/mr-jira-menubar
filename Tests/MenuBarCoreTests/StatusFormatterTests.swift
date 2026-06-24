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
}
