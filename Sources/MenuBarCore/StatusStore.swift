import Foundation

public struct GitLabCounts: Equatable {
    public let open: Int
    public let ready: Int
    public init(open: Int, ready: Int) { self.open = open; self.ready = ready }
}

public struct JiraCounts: Equatable {
    public let backlog: Int
    public let inProgress: Int
    public let testingAwaiting: Int
    public let testingMovedOn: Int
    public init(backlog: Int, inProgress: Int, testingAwaiting: Int = 0, testingMovedOn: Int = 0) {
        self.backlog = backlog
        self.inProgress = inProgress
        self.testingAwaiting = testingAwaiting
        self.testingMovedOn = testingMovedOn
    }
}

public struct GitHubCounts: Equatable {
    public let open: Int
    public let approved: Int
    public init(open: Int, approved: Int) { self.open = open; self.approved = approved }
}

public struct SourceResult<T: Equatable>: Equatable {
    public var value: T?
    public var error: String?
    public var isLoading: Bool
    public init(value: T? = nil, error: String? = nil, isLoading: Bool = false) {
        self.value = value
        self.error = error
        self.isLoading = isLoading
    }
}

@MainActor
public final class StatusStore {
    public private(set) var gitlab = SourceResult<GitLabCounts>()
    public private(set) var jira = SourceResult<JiraCounts>()
    public private(set) var github = SourceResult<GitHubCounts>()
    public private(set) var lastRefresh: Date?
    public var onUpdate: (@MainActor () -> Void)?

    private var gitlabClient: GitLabFetching?
    private var jiraClient: JiraFetching?
    private var githubClient: GitHubFetching?
    private let interval: TimeInterval
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    public init(gitlabClient: GitLabFetching? = nil, jiraClient: JiraFetching? = nil, githubClient: GitHubFetching? = nil, interval: TimeInterval = 300) {
        self.gitlabClient = gitlabClient
        self.jiraClient = jiraClient
        self.githubClient = githubClient
        self.interval = interval
    }

    public func setClients(gitlabClient: GitLabFetching? = nil, jiraClient: JiraFetching? = nil, githubClient: GitHubFetching? = nil) {
        self.gitlabClient = gitlabClient
        self.jiraClient = jiraClient
        self.githubClient = githubClient
    }

    public func start() {
        scheduleTimer()
        refreshNow()
    }

    public func scheduleTimer() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func refreshNow() {
        guard refreshTask == nil else { return }

        startRefreshTask()
    }

    public func restartRefresh() {
        refreshTask?.cancel()
        startRefreshTask()
    }

    private func startRefreshTask() {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            await self?.refresh()
            self?.clearRefreshTask(ifGeneration: generation)
        }
    }

    private func clearRefreshTask(ifGeneration generation: Int) {
        guard generation == refreshGeneration else { return }

        refreshTask = nil
    }

    public func refresh() async {
        if gitlabClient != nil { gitlab.isLoading = true } else { gitlab = SourceResult() }
        if jiraClient != nil { jira.isLoading = true } else { jira = SourceResult() }
        if githubClient != nil { github.isLoading = true } else { github = SourceResult() }
        onUpdate?()
        async let g: Void = refreshGitLab()
        async let j: Void = refreshJira()
        async let gh: Void = refreshGitHub()
        _ = await (g, j, gh)

        if Task.isCancelled { return }

        lastRefresh = Date()
        onUpdate?()
    }

    private func refreshGitLab() async {
        guard let gitlabClient else { return }

        do {
            async let open = gitlabClient.fetchOpenMRCount()
            async let ready = gitlabClient.fetchReadyToMergeCount()
            let counts = GitLabCounts(open: try await open, ready: try await ready)

            if Task.isCancelled { return }

            gitlab = SourceResult(value: counts, error: nil, isLoading: false)
        } catch {
            if Task.isCancelled { return }

            gitlab = SourceResult(value: gitlab.value, error: Self.message(error), isLoading: false)
        }
        onUpdate?()
    }

    private func refreshJira() async {
        guard let jiraClient else { return }

        do {
            async let backlog = jiraClient.backlogCount()
            async let inProgress = jiraClient.inProgressCount()
            async let testingAwaiting = jiraClient.testingAwaitingCount()
            async let testingMovedOn = jiraClient.testingMovedOnCount()
            let counts = JiraCounts(
                backlog: try await backlog,
                inProgress: try await inProgress,
                testingAwaiting: try await testingAwaiting,
                testingMovedOn: try await testingMovedOn)

            if Task.isCancelled { return }

            jira = SourceResult(value: counts, error: nil, isLoading: false)
        } catch {
            if Task.isCancelled { return }

            jira = SourceResult(value: jira.value, error: Self.message(error), isLoading: false)
        }
        onUpdate?()
    }

    private func refreshGitHub() async {
        guard let githubClient else { return }

        do {
            async let open = githubClient.fetchOpenPRCount()
            async let approved = githubClient.fetchApprovedPRCount()
            let counts = GitHubCounts(open: try await open, approved: try await approved)

            if Task.isCancelled { return }

            github = SourceResult(value: counts, error: nil, isLoading: false)
        } catch {
            if Task.isCancelled { return }

            github = SourceResult(value: github.value, error: Self.message(error), isLoading: false)
        }
        onUpdate?()
    }

    public static func message(_ error: Error) -> String {
        switch error {
        case let e as GitLabError: return e.description
        case let e as JiraError: return e.description
        case let e as GitHubError: return e.description
        default: return error.localizedDescription
        }
    }
}
