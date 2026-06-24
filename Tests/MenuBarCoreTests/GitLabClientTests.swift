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
}
