import Foundation

public struct GitLabCounts: Equatable {
    public let open: Int
    public let ready: Int
    public init(open: Int, ready: Int) { self.open = open; self.ready = ready }
}

public struct JiraCounts: Equatable {
    public let backlog: Int
    public let inProgress: Int
    public init(backlog: Int, inProgress: Int) { self.backlog = backlog; self.inProgress = inProgress }
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
    public private(set) var lastRefresh: Date?
    public var onUpdate: (@MainActor () -> Void)?

    private var gitlabClient: GitLabFetching
    private var jiraClient: JiraFetching
    private let interval: TimeInterval
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    public init(gitlabClient: GitLabFetching, jiraClient: JiraFetching, interval: TimeInterval = 300) {
        self.gitlabClient = gitlabClient
        self.jiraClient = jiraClient
        self.interval = interval
    }

    public func setClients(gitlabClient: GitLabFetching, jiraClient: JiraFetching) {
        self.gitlabClient = gitlabClient
        self.jiraClient = jiraClient
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
        gitlab.isLoading = true
        jira.isLoading = true
        onUpdate?()
        async let g: Void = refreshGitLab()
        async let j: Void = refreshJira()
        _ = await (g, j)

        if Task.isCancelled { return }

        lastRefresh = Date()
        onUpdate?()
    }

    private func refreshGitLab() async {
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
        do {
            async let backlog = jiraClient.backlogCount()
            async let inProgress = jiraClient.inProgressCount()
            let counts = JiraCounts(backlog: try await backlog, inProgress: try await inProgress)

            if Task.isCancelled { return }

            jira = SourceResult(value: counts, error: nil, isLoading: false)
        } catch {
            if Task.isCancelled { return }

            jira = SourceResult(value: jira.value, error: Self.message(error), isLoading: false)
        }
        onUpdate?()
    }

    public static func message(_ error: Error) -> String {
        switch error {
        case let e as CredentialsError: return e.description
        case let e as GitLabError: return e.description
        case let e as JiraError: return e.description
        default: return error.localizedDescription
        }
    }
}
