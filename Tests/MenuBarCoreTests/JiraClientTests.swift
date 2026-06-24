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
