import Foundation

protocol RejectionCandidateFetching: Sendable {
    func myself() async throws -> String
    func rejectionCandidates() async throws -> [IssueTransitions]
}

extension JiraClient: RejectionCandidateFetching {}

actor RejectedIssuesService {
    private let jira: any RejectionCandidateFetching
    private let gitlab: any MergeRequestLookup
    private var verdicts: [String: Bool] = [:]

    init(jira: any RejectionCandidateFetching, gitlab: any MergeRequestLookup) {
        self.jira = jira
        self.gitlab = gitlab
    }

    func rejectedCount() async throws -> Int {
        let me = try await jira.myself()
        let candidates = try await jira.rejectionCandidates()
        var count = 0

        for candidate in candidates {
            guard let bouncedAt = JiraClient.rejectionCycle(in: candidate.transitions, me: me) else { continue }

            if await hasVerifiedMR(key: candidate.key, before: bouncedAt) { count += 1 }
        }

        return count
    }

    // Fail-open: a GitLab error never excludes an issue and is never cached,
    // so the next refresh retries; only confirmed verdicts persist.
    private func hasVerifiedMR(key: String, before bouncedAt: Date) async -> Bool {
        if let cached = verdicts[key] { return cached }

        guard let verdict = try? await gitlab.hasMyMergeRequest(referencing: key, createdBefore: bouncedAt) else { return true }

        verdicts[key] = verdict
        return verdict
    }
}

struct JiraWithRejectionService: JiraFetching {
    let base: JiraClient
    let service: RejectedIssuesService

    func backlogCount() async throws -> Int { try await base.backlogCount() }
    func inProgressCount() async throws -> Int { try await base.inProgressCount() }
    func testingAwaitingCount() async throws -> Int { try await base.testingAwaitingCount() }
    func testingAcceptedCount() async throws -> Int { try await base.testingAcceptedCount() }
    func testingRejectedCount() async throws -> Int { try await service.rejectedCount() }
}
