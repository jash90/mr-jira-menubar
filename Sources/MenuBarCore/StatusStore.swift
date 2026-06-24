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

    private let gitlabClient: GitLabFetching
    private let jiraClient: JiraFetching
    private let interval: TimeInterval
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    public init(gitlabClient: GitLabFetching, jiraClient: JiraFetching, interval: TimeInterval = 300) {
        self.gitlabClient = gitlabClient
        self.jiraClient = jiraClient
        self.interval = interval
    }

    public func start() {
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }

    public func refreshNow() {
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            await self?.refresh()
            self?.refreshTask = nil
        }
    }

    public func refresh() async {
        gitlab.isLoading = true
        jira.isLoading = true
        onUpdate?()
        async let g: Void = refreshGitLab()
        async let j: Void = refreshJira()
        _ = await (g, j)
        lastRefresh = Date()
        onUpdate?()
    }

    private func refreshGitLab() async {
        do {
            async let open = gitlabClient.fetchOpenMRCount()
            async let ready = gitlabClient.fetchReadyToMergeCount()
            gitlab = SourceResult(value: GitLabCounts(open: try await open, ready: try await ready),
                                  error: nil, isLoading: false)
        } catch {
            gitlab = SourceResult(value: gitlab.value, error: Self.message(error), isLoading: false)
        }
        onUpdate?()
    }

    private func refreshJira() async {
        do {
            async let backlog = jiraClient.backlogCount()
            async let inProgress = jiraClient.inProgressCount()
            jira = SourceResult(value: JiraCounts(backlog: try await backlog, inProgress: try await inProgress),
                                error: nil, isLoading: false)
        } catch {
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
