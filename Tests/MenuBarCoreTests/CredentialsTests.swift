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

    func testThrowsTokenMissingWhenHostBlockHasNoTokenLine() {
        let yaml = """
        hosts:
            drm-gitlab.redlabs.pl:
                api_host: drm-gitlab.redlabs.pl
                user: bartlomiej.zimny
        """
        XCTAssertThrowsError(try Credentials.parseToken(host: "drm-gitlab.redlabs.pl", yaml: yaml, file: "/p/config.yml")) { error in
            XCTAssertEqual(error as? CredentialsError, .tokenMissing("drm-gitlab.redlabs.pl", file: "/p/config.yml"))
        }
    }

    func testThrowsTokenMissingWhenTokenValueIsEmpty() {
        let yaml = """
        hosts:
            drm-gitlab.redlabs.pl:
                token: ""
                user: bartlomiej.zimny
        """
        XCTAssertThrowsError(try Credentials.parseToken(host: "drm-gitlab.redlabs.pl", yaml: yaml, file: "/p/config.yml")) { error in
            XCTAssertEqual(error as? CredentialsError, .tokenMissing("drm-gitlab.redlabs.pl", file: "/p/config.yml"))
        }
    }

    func testJiraTokenThrowsFileMissingWhenFileAbsent() {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("jira-token-absent-\(UUID().uuidString)")
        let creds = Credentials(glabConfigPath: "/nonexistent", jiraTokenPath: path)
        XCTAssertThrowsError(try creds.jiraToken()) { error in
            XCTAssertEqual(error as? CredentialsError, .fileMissing(path))
        }
    }

    func testJiraTokenThrowsFileMissingWhenFileWhitespaceOnly() throws {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("jira-token-blank-\(UUID().uuidString)")
        try "   \n\t\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let creds = Credentials(glabConfigPath: "/nonexistent", jiraTokenPath: path)
        XCTAssertThrowsError(try creds.jiraToken()) { error in
            XCTAssertEqual(error as? CredentialsError, .fileMissing(path))
        }
    }
}
