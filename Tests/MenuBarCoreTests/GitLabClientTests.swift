import XCTest
@testable import MenuBarCore

final class GitLabClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func testFetchOpenMRCountReadsXTotalHeader() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url!.path, "/api/v4/merge_requests")
            XCTAssertTrue(req.url!.query!.contains("scope=created_by_me"))
            XCTAssertEqual(req.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "tok")
            return .init(statusCode: 200, headers: ["X-Total": "8"], body: Data("[]".utf8))
        }
        let client = GitLabClient(host: "gl.example", token: "tok", session: StubURLProtocol.session())
        let count = try await client.fetchOpenMRCount()
        XCTAssertEqual(count, 8)
    }

    func testReadyToMergeCountsOnlyMRsWithTwoApprovals() async throws {
        StubURLProtocol.handler = { req in
            let path = req.url!.path
            if path.contains("/merge_requests/10/approvals") {
                return .init(statusCode: 200, body: Data(#"{"approved_by":[{"user":{}},{"user":{}}]}"#.utf8))
            }
            if path.contains("/merge_requests/11/approvals") {
                return .init(statusCode: 200, body: Data(#"{"approved_by":[{"user":{}}]}"#.utf8))
            }
            if path == "/api/v4/merge_requests" {
                return .init(statusCode: 200, body: Data(#"[{"project_id":1,"iid":10},{"project_id":1,"iid":11}]"#.utf8))
            }
            return .init(statusCode: 404)
        }
        let client = GitLabClient(host: "gl.example", token: "tok", session: StubURLProtocol.session())
        let count = try await client.fetchReadyToMergeCount()
        XCTAssertEqual(count, 1)
    }

    func testReadyToMergeFollowsPaginationViaNextPageHeader() async throws {
        StubURLProtocol.handler = { req in
            let path = req.url!.path
            if path.contains("/merge_requests/10/approvals") || path.contains("/merge_requests/11/approvals") {
                return .init(statusCode: 200, body: Data(#"{"approved_by":[{"user":{}},{"user":{}}]}"#.utf8))
            }
            if path == "/api/v4/merge_requests" {
                let query = req.url!.query ?? ""
                if query.contains("page=2") {
                    return .init(statusCode: 200, body: Data(#"[{"project_id":1,"iid":11}]"#.utf8))
                }
                return .init(
                    statusCode: 200,
                    headers: ["X-Next-Page": "2"],
                    body: Data(#"[{"project_id":1,"iid":10}]"#.utf8)
                )
            }
            return .init(statusCode: 404)
        }
        let client = GitLabClient(host: "gl.example", token: "tok", session: StubURLProtocol.session())
        let count = try await client.fetchReadyToMergeCount()
        XCTAssertEqual(count, 2)
    }

    func testFetchOpenMRCountThrowsStatusOn401() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 401) }
        let client = GitLabClient(host: "gl.example", token: "tok", session: StubURLProtocol.session())
        do {
            _ = try await client.fetchOpenMRCount()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? GitLabError, .status(401))
        }
    }

    func testFetchOpenMRCountThrowsMissingTotalWhenHeaderAbsent() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 200, body: Data("[]".utf8)) }
        let client = GitLabClient(host: "gl.example", token: "tok", session: StubURLProtocol.session())
        do {
            _ = try await client.fetchOpenMRCount()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? GitLabError, .missingTotal)
        }
    }

    func testFetchOpenMRCountThrowsMissingTotalWhenHeaderNonNumeric() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 200, headers: ["X-Total": "abc"], body: Data("[]".utf8)) }
        let client = GitLabClient(host: "gl.example", token: "tok", session: StubURLProtocol.session())
        do {
            _ = try await client.fetchOpenMRCount()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? GitLabError, .missingTotal)
        }
    }

    func testStatus401DescriptionMentionsToken() {
        XCTAssertTrue(GitLabError.status(401).description.contains("401"))
        XCTAssertTrue(GitLabError.status(401).description.lowercased().contains("token"))
    }
}
