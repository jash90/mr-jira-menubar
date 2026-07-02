import XCTest
@testable import MenuBarCore

final class JiraClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    // Regression: these host forms made URLComponents.url nil → force-unwrap trap (SIGTRAP).
    func testHostIsNormalizedSoUrlBuildsWithoutCrash() {
        XCTAssertEqual(normalizedHost("https://jira.example.com"), "jira.example.com")
        XCTAssertEqual(normalizedHost("jira.example.com/"), "jira.example.com")
        XCTAssertEqual(normalizedHost("  jira.example.com  "), "jira.example.com")
        XCTAssertEqual(JiraClient(host: "https://jira.example.com/", token: "t").host, "jira.example.com")
    }

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

    func testInProgressJQLMatchesSpec() {
        XCTAssertEqual(
            JiraClient.inProgressJQL,
            #"assignee = currentUser() AND resolution = Unresolved AND status = "In Progress""#
        )
    }

    func testTestingAwaitingJQLMatchesSpec() {
        XCTAssertEqual(
            JiraClient.testingAwaitingJQL,
            #"(assignee = currentUser() OR status CHANGED TO "Internal testing" BY currentUser()) AND status CHANGED TO "Internal testing" AND status = "Internal testing""#
        )
    }

    func testTestingAcceptedJQLMatchesSpec() {
        XCTAssertEqual(
            JiraClient.testingAcceptedJQL,
            #"(assignee = currentUser() OR status CHANGED TO "Internal testing" BY currentUser()) AND status CHANGED TO "Internal testing" AND status not in ("Internal testing", "Backlog", "To Do", "New", "In Progress", "Code review")"#
        )
    }

    func testTestingRejectedJQLMatchesSpec() {
        XCTAssertEqual(
            JiraClient.testingRejectedJQL,
            #"(assignee = currentUser() OR status CHANGED TO "Internal testing" BY currentUser()) AND status CHANGED TO "Internal testing" AND status in ("Backlog", "To Do", "New", "In Progress", "Code review")"#
        )
    }

    func testCountThrowsStatusOn401() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 401) }
        let client = JiraClient(host: "jira.example", token: "tok", session: StubURLProtocol.session())
        do {
            _ = try await client.count(jql: "anything")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? JiraError, .status(401))
        }
    }

    func testStatus401DescriptionMentionsToken() {
        XCTAssertTrue(JiraError.status(401).description.contains("401"))
        XCTAssertTrue(JiraError.status(401).description.lowercased().contains("token"))
    }
}
