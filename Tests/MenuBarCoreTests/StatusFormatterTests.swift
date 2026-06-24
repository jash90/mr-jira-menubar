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
