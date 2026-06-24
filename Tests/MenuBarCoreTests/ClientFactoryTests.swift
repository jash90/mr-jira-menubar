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

    func testMakeGitHubReturnsNilWhenInactiveAndClientWhenActive() {
        XCTAssertNil(ClientFactory.makeGitHub(AppConfig()))  // empty github token
        let active = AppConfig(githubHost: "api.github.com", githubToken: "t")
        XCTAssertNotNil(ClientFactory.makeGitHub(active))
    }
}
