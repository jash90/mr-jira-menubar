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

    func testMakeGitLabReturnsNilWhenInactiveAndClientWhenActive() {
        XCTAssertNil(ClientFactory.makeGitLab(AppConfig()))  // empty gitlab token
        let active = AppConfig(gitlabHost: "gl.example", gitlabToken: "t")
        XCTAssertEqual((ClientFactory.makeGitLab(active) as? GitLabClient)?.host, "gl.example")
    }

    func testMakeJiraReturnsNilWhenInactiveAndClientWhenActive() {
        XCTAssertNil(ClientFactory.makeJira(AppConfig()))  // empty jira token
        let active = AppConfig(jiraHost: "jira.example", jiraToken: "t")
        XCTAssertEqual((ClientFactory.makeJira(active) as? JiraClient)?.host, "jira.example")
    }

    func testMakeJiraWrapsWithRejectionServiceWhenGitLabActive() {
        let both = AppConfig(
            gitlabHost: "gl.example",
            gitlabToken: "gt",
            jiraHost: "jira.example",
            jiraToken: "jt"
        )
        XCTAssertTrue(ClientFactory.makeJira(both) is JiraWithRejectionService)

        let jiraOnly = AppConfig(jiraHost: "jira.example", jiraToken: "jt")
        XCTAssertTrue(ClientFactory.makeJira(jiraOnly) is JiraClient)
    }
}
