import XCTest
@testable import MenuBarCore

final class ClientFactoryTests: XCTestCase {
    func testMakeRoutesHostsToCorrectClients() {
        let config = AppConfig(
            gitlabHost: "gl.example",
            gitlabToken: "gt",
            jiraHost: "jira.example",
            jiraToken: "jt"
        )
        let (gitlab, jira) = ClientFactory.make(config)
        XCTAssertEqual((gitlab as? GitLabClient)?.host, "gl.example")
        XCTAssertEqual((jira as? JiraClient)?.host, "jira.example")
    }
}
