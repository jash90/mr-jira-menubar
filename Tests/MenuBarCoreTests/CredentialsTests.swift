import XCTest
@testable import MenuBarCore

final class CredentialsTests: XCTestCase {
    let sampleYAML = """
    hosts:
        gitlab.com:
            token: WRONGTOKEN
            user: someone
        drm-gitlab.redlabs.pl:
            api_host: drm-gitlab.redlabs.pl
            user: bartlomiej.zimny
            token: GLPAT-correct-123
    """

    func testParsesTokenForRequestedHost() throws {
        let token = try Credentials.parseToken(host: "drm-gitlab.redlabs.pl", yaml: sampleYAML, file: "f")
        XCTAssertEqual(token, "GLPAT-correct-123")
    }

    func testThrowsHostMissingWithPath() {
        XCTAssertThrowsError(try Credentials.parseToken(host: "no.such.host", yaml: sampleYAML, file: "/p/config.yml")) { error in
            XCTAssertEqual(error as? CredentialsError, .hostMissing("no.such.host", file: "/p/config.yml"))
        }
    }

    func testJiraTokenTrimsWhitespace() throws {
        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("jira-token-test")
        try "  abc123\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let creds = Credentials(glabConfigPath: "/nonexistent", jiraTokenPath: path)
        XCTAssertEqual(try creds.jiraToken(), "abc123")
    }
}
