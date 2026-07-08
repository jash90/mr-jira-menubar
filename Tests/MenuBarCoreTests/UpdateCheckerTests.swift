import XCTest
@testable import MenuBarCore

private struct FakeReleases: ReleaseFetching {
    let info: ReleaseInfo
    func fetchLatestRelease() async throws -> ReleaseInfo { info }
}

private struct FailingReleases: ReleaseFetching {
    func fetchLatestRelease() async throws -> ReleaseInfo { throw URLError(.notConnectedToInternet) }
}

final class UpdateCheckerTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func testReleaseClientParsesTagVersionAndFirstDmgAsset() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url!.host, "api.github.com")
            XCTAssertTrue(req.url!.path.hasSuffix("/releases/latest"))
            XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertFalse((req.value(forHTTPHeaderField: "User-Agent") ?? "").isEmpty)
            let json = """
            {"tag_name":"v1.3.0",
             "html_url":"https://github.com/jash90/mr-jira-menubar/releases/tag/v1.3.0",
             "assets":[{"name":"notes.txt","browser_download_url":"https://x/notes.txt"},
                       {"name":"MRJiraMenuBar-1.3.0.dmg","browser_download_url":"https://x/app.dmg"}]}
            """
            return .init(statusCode: 200, body: Data(json.utf8))
        }
        let client = GitHubReleaseClient(session: StubURLProtocol.session())
        let info = try await client.fetchLatestRelease()
        XCTAssertEqual(info.tag, "v1.3.0")
        XCTAssertEqual(info.version, "1.3.0")
        XCTAssertEqual(info.dmgURL?.absoluteString, "https://x/app.dmg")
        XCTAssertEqual(info.htmlURL?.absoluteString, "https://github.com/jash90/mr-jira-menubar/releases/tag/v1.3.0")
    }

    func testReleaseClientSendsBearerWhenTokenPresent() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            return .init(statusCode: 200, body: Data(#"{"tag_name":"v1.0.0","assets":[]}"#.utf8))
        }
        let client = GitHubReleaseClient(token: "tok", session: StubURLProtocol.session())
        _ = try await client.fetchLatestRelease()
    }

    func testNotFoundMapsToError() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 404, body: Data(#"{"message":"Not Found"}"#.utf8)) }
        let client = GitHubReleaseClient(session: StubURLProtocol.session())
        do {
            _ = try await client.fetchLatestRelease()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? UpdateError, .status(404))
        }
    }

    @MainActor
    func testCheckSetsAvailableUpdateWhenNewer() async {
        let checker = UpdateChecker(
            client: FakeReleases(info: ReleaseInfo(version: "1.3.0", tag: "v1.3.0", dmgURL: nil, htmlURL: nil)),
            currentVersion: "1.2.0")
        await checker.check()
        XCTAssertEqual(checker.availableUpdate?.version, "1.3.0")
    }

    @MainActor
    func testCheckLeavesNilWhenNotNewer() async {
        let checker = UpdateChecker(
            client: FakeReleases(info: ReleaseInfo(version: "1.2.0", tag: "v1.2.0", dmgURL: nil, htmlURL: nil)),
            currentVersion: "1.2.0")
        await checker.check()
        XCTAssertNil(checker.availableUpdate)
    }

    @MainActor
    func testCheckSwallowsFetchError() async {
        let checker = UpdateChecker(client: FailingReleases(), currentVersion: "1.2.0")
        await checker.check()
        XCTAssertNil(checker.availableUpdate)
    }
}
