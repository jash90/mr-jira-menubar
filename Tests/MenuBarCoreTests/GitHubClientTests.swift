import XCTest
@testable import MenuBarCore

final class GitHubClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func testOpenCountParsesTotalAndSendsHeaders() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url!.path, "/search/issues")
            let q = req.url!.query ?? ""
            XCTAssertTrue(q.contains("is:pr") || q.contains("is%3Apr"))
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertFalse((req.value(forHTTPHeaderField: "User-Agent") ?? "").isEmpty)
            return .init(statusCode: 200, body: Data(#"{"total_count":7,"items":[]}"#.utf8))
        }
        let client = GitHubClient(host: "api.github.com", token: "tok", session: StubURLProtocol.session())
        let count = try await client.fetchOpenPRCount()
        XCTAssertEqual(count, 7)
    }

    func testApprovedQueryIncludesReviewApproved() async throws {
        StubURLProtocol.handler = { req in
            let q = (req.url!.query ?? "").removingPercentEncoding ?? ""
            XCTAssertTrue(q.contains("review:approved"))
            return .init(statusCode: 200, body: Data(#"{"total_count":2,"items":[]}"#.utf8))
        }
        let client = GitHubClient(token: "tok", session: StubURLProtocol.session())
        let count = try await client.fetchApprovedPRCount()
        XCTAssertEqual(count, 2)
    }

    func testUnauthorizedMapsToStatus401() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 401, body: Data(#"{"message":"Bad credentials"}"#.utf8)) }
        let client = GitHubClient(token: "tok", session: StubURLProtocol.session())
        do {
            _ = try await client.fetchOpenPRCount()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .status(401))
        }
    }

    func testEnterpriseHostUsesApiV3Path() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url!.path, "/api/v3/search/issues")
            return .init(statusCode: 200, body: Data(#"{"total_count":0,"items":[]}"#.utf8))
        }
        let client = GitHubClient(host: "ghe.example.com", token: "tok", session: StubURLProtocol.session())
        _ = try await client.fetchOpenPRCount()
    }
}
