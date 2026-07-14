import XCTest
@testable import MenuBarCore

final class JiraClientTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    // Regression: these host forms made URLComponents.url nil → force-unwrap trap (SIGTRAP).
    func testHostIsNormalizedSoUrlBuildsWithoutCrash() {
        XCTAssertEqual(normalizedHost("https://jira.example.com"), "jira.example.com")
        XCTAssertEqual(normalizedHost("jira.example.com/"), "jira.example.com")
        XCTAssertEqual(normalizedHost("  jira.example.com  "), "jira.example.com")
        XCTAssertEqual(JiraClient(host: "https://jira.example.com/", token: "t").host, "jira.example.com")
    }

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

    func testInProgressJQLMatchesSpec() {
        XCTAssertEqual(
            JiraClient.inProgressJQL,
            #"assignee = currentUser() AND resolution = Unresolved AND status = "In Progress""#
        )
    }

    func testTestingAwaitingJQLMatchesSpec() {
        XCTAssertEqual(
            JiraClient.testingAwaitingJQL,
            #"(assignee = currentUser() OR status CHANGED TO "Internal testing" BY currentUser()) AND status CHANGED TO "Internal testing" AND status = "Internal testing""#
        )
    }

    func testTestingAcceptedJQLMatchesSpec() {
        XCTAssertEqual(
            JiraClient.testingAcceptedJQL,
            #"(assignee = currentUser() OR status CHANGED TO "Internal testing" BY currentUser()) AND status CHANGED TO "Internal testing" AND status not in ("Internal testing", "Backlog", "To Do", "New", "In Progress", "Code review")"#
        )
    }

    func testTestingRejectedJQLMatchesSpec() {
        XCTAssertEqual(
            JiraClient.testingRejectedJQL,
            #"(assignee = currentUser() OR status CHANGED TO "Internal testing" BY currentUser()) AND status CHANGED TO "Internal testing" AND status in ("Backlog", "To Do", "New", "In Progress", "Code review")"#
        )
    }

    // Scenario like SOFKRS-7983: reviewer moves the ticket to testing, but the tested work
    // is mine — the developer is the author of the last move to Code review before testing.
    func testDeveloperOfLastTestingRoundIsCodeReviewAuthor() {
        let transitions = [
            StatusTransition(author: "me", toStatus: "In Progress"),
            StatusTransition(author: "me", toStatus: "Code review"),
            StatusTransition(author: "reviewer", toStatus: "Internal testing"),
            StatusTransition(author: "tester", toStatus: "In Progress"),
        ]
        XCTAssertEqual(JiraClient.developerOfLastTestingRound(transitions), "me")
    }

    // Scenario like SOFKRS-6260: someone else's round got rejected, I took the ticket over
    // afterwards — my transitions after the last testing round must not count.
    func testDeveloperOfLastTestingRoundIgnoresTakeoverAfterRejection() {
        let transitions = [
            StatusTransition(author: "other.dev", toStatus: "In Progress"),
            StatusTransition(author: "other.dev", toStatus: "Code review"),
            StatusTransition(author: "reviewer", toStatus: "Internal testing"),
            StatusTransition(author: "tester", toStatus: "In Progress"),
            StatusTransition(author: "me", toStatus: "In Progress"),
            StatusTransition(author: "me", toStatus: "Code review"),
        ]
        XCTAssertEqual(JiraClient.developerOfLastTestingRound(transitions), "other.dev")
    }

    func testDeveloperOfLastTestingRoundFallsBackToTestingTransitionAuthor() {
        let transitions = [
            StatusTransition(author: "me", toStatus: "In Progress"),
            StatusTransition(author: "me", toStatus: "Internal testing"),
            StatusTransition(author: "tester", toStatus: "Acceptance"),
        ]
        XCTAssertEqual(JiraClient.developerOfLastTestingRound(transitions), "me")
    }

    func testDeveloperOfLastTestingRoundIsNilWithoutTestingTransition() {
        let transitions = [
            StatusTransition(author: "me", toStatus: "In Progress"),
            StatusTransition(author: "me", toStatus: "Code review"),
        ]
        XCTAssertNil(JiraClient.developerOfLastTestingRound(transitions))
    }

    func testSearchTransitionsPaginatesAndParsesKeysAndDates() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url!.path, "/rest/api/2/search")
            let query = req.url!.query!
            XCTAssertTrue(query.contains("expand=changelog"))
            let pageOne = #"""
                {"total":2,"issues":[
                {"key":"SOFKRS-1","changelog":{"histories":[
                {"author":{"name":"me"},"created":"2026-01-10T10:00:00.000+0100","items":[{"field":"status","toString":"Internal testing"}]}]}}]}
                """#
            let pageTwo = #"""
                {"total":2,"issues":[
                {"key":"SOFKRS-2","changelog":{"histories":[
                {"author":{"name":"tester"},"items":[{"field":"status","toString":"In Progress"}]}]}}]}
                """#
            let body = query.contains("startAt=0") ? pageOne : pageTwo
            return .init(statusCode: 200, body: Data(body.utf8))
        }
        let client = JiraClient(host: "jira.example", token: "tok", session: StubURLProtocol.session())
        let issues = try await client.searchTransitions(jql: "anything")
        XCTAssertEqual(issues.map(\.key), ["SOFKRS-1", "SOFKRS-2"])
        let expectedDate = JiraClient.changelogDateFormatter.date(from: "2026-01-10T10:00:00.000+0100")!
        XCTAssertEqual(issues[0].transitions, [StatusTransition(author: "me", toStatus: "Internal testing", date: expectedDate)])
        XCTAssertEqual(issues[1].transitions[0].date, .distantFuture)
    }

    func testAcceptedCountFiltersOutOtherDevelopersRounds() async throws {
        StubURLProtocol.handler = { req in
            if req.url!.path == "/rest/api/2/myself" {
                return .init(statusCode: 200, body: Data(#"{"name":"me"}"#.utf8))
            }

            XCTAssertEqual(req.url!.path, "/rest/api/2/search")
            let mine = #"""
                {"key":"SOFKRS-1","changelog":{"histories":[
                {"author":{"name":"me"},"items":[{"field":"status","toString":"Code review"}]},
                {"author":{"name":"reviewer"},"items":[{"field":"status","toString":"Internal testing"}]},
                {"author":{"name":"tester"},"items":[{"field":"status","toString":"Acceptance"}]}]}}
                """#
            let takenOver = #"""
                {"key":"SOFKRS-2","changelog":{"histories":[
                {"author":{"name":"other.dev"},"items":[{"field":"status","toString":"Code review"}]},
                {"author":{"name":"reviewer"},"items":[{"field":"status","toString":"Internal testing"}]},
                {"author":{"name":"tester"},"items":[{"field":"status","toString":"Acceptance"}]}]}}
                """#
            let body = #"{"total":2,"issues":["# + mine + "," + takenOver + "]}"
            return .init(statusCode: 200, body: Data(body.utf8))
        }
        let client = JiraClient(host: "jira.example", token: "tok", session: StubURLProtocol.session())
        let count = try await client.testingAcceptedCount()
        XCTAssertEqual(count, 1)
    }

    func testCountThrowsStatusOn401() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 401) }
        let client = JiraClient(host: "jira.example", token: "tok", session: StubURLProtocol.session())
        do {
            _ = try await client.count(jql: "anything")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? JiraError, .status(401))
        }
    }

    func testStatus401DescriptionMentionsToken() {
        XCTAssertTrue(JiraError.status(401).description.contains("401"))
        XCTAssertTrue(JiraError.status(401).description.lowercased().contains("token"))
    }
}
