import Foundation

/// Polls GitHub and keeps the feed and review categories current.
public final class FeedEngine {
    public struct Snapshot {
        public var newItems: [FeedItem]
        public var categories: [CategoryResult]
        /// Your own open PRs, split into `myPRGroups`.
        public var mine: [CategoryResult]
        /// Your merged PRs, newest merge first. At most one search page.
        public var merged: [ReviewPR]
        public var errors: [String]
        /// True when this refresh only loaded the lookback window, so nothing should pop up.
        public var isFirstRun: Bool
    }

    public private(set) var config = Config()
    public private(set) var state: FeedState
    public private(set) var pollInterval: TimeInterval = 60

    private var client: GitHubClient?
    private var me: String?
    private var myTeams: [String] = []
    private var teamMembersCache: (team: String, logins: [String], fetchedAt: Date)?

    private let persist: Bool

    public init(state: FeedState = FeedStore.load(), persist: Bool = true) {
        self.state = state
        self.persist = persist
    }

    private func save() {
        if persist { try? FeedStore.save(state) }
    }

    public func refresh() async throws -> Snapshot {
        config = try ConfigStore.load()
        let client = try self.client ?? GitHubClient(token: TokenProvider.token())
        self.client = client
        if me == nil {
            me = try await client.viewerLogin()
            myTeams = (try? await client.myTeams()) ?? []
        }

        var errors: [String] = []
        let isFirstRun = state.lastPoll == nil
        let newItems = try await refreshFeed(client: client, errors: &errors)
        let categories = await refreshCategories(client: client, errors: &errors)
        let mine = await refreshMine(client: client, errors: &errors)
        let merged = await refreshMerged(client: client, errors: &errors)
        state.prune()
        save()
        return Snapshot(newItems: newItems, categories: categories, mine: mine, merged: merged, errors: errors, isFirstRun: isFirstRun)
    }

    private func refreshFeed(client: GitHubClient, errors: inout [String]) async throws -> [FeedItem] {
        guard let me else { return [] }
        let now = Date()
        let lookbackStart = now.addingTimeInterval(-Double(config.lookbackDays) * 86_400)
        // Overlap a few minutes so activity that lands mid-poll isn't missed. Merge dedupes by id.
        let since = (state.lastPoll ?? lookbackStart).addingTimeInterval(-300)

        let page = try await client.notifications(since: since, ifModifiedSince: state.lastModified)
        pollInterval = TimeInterval(max(config.pollIntervalSeconds, page.pollInterval ?? 0))
        state.lastPoll = now
        if page.notModified { return [] }
        state.lastModified = page.lastModified

        let context = ClassifierContext(
            me: me,
            teams: config.mentionTeams ?? myTeams,
            ignoredUsers: Set(config.ignoredUsers.map { $0.lowercased() }),
            ignoreBots: config.ignoreBots,
            approvalsWithComments: config.notifyApprovalsWithComments
        )

        let threads = page.threads.compactMap { thread in
            thread.subject.type == "PullRequest" ? PRRef(apiURL: thread.subject.url).map { (thread, $0) } : nil
        }
        let changed = threads.filter { thread, ref in
            thread.updatedAt > (state.checkedAt[ref.key] ?? lookbackStart).addingTimeInterval(-300)
        }.map(\.1)
        let details = await fetchDetails(Array(Set(changed)), client: client)

        var added: [FeedItem] = []
        for (thread, ref) in threads {
            state.threadIds[ref.key] = thread.id
            switch details[ref] {
            case .success(let detail):
                let since = (state.checkedAt[ref.key] ?? lookbackStart).addingTimeInterval(-300)
                added += state.merge(Classifier.classify(detail, since: since, context: context), for: detail)
                state.checkedAt[ref.key] = now
            case .failure(let error):
                errors.append(error.localizedDescription)
            case nil:
                break
            }
            if !thread.unread, let lastReadAt = thread.lastReadAt {
                state.applyRemoteRead(pr: ref, lastReadAt: lastReadAt)
            }
        }
        let unread = Set(state.items.filter { !$0.read }.map(\.id))
        return added.filter { unread.contains($0.id) }
    }

    private func fetchDetails(_ refs: [PRRef], client: GitHubClient, concurrency: Int = 8) async -> [PRRef: Result<PRDetail, Error>] {
        await withTaskGroup(of: (PRRef, Result<PRDetail, Error>).self) { group in
            var pending = refs.makeIterator()
            var results: [PRRef: Result<PRDetail, Error>] = [:]
            for _ in 0..<concurrency {
                guard let ref = pending.next() else { break }
                group.addTask { await Self.load(ref, client) }
            }
            while let (ref, result) = await group.next() {
                results[ref] = result
                if let next = pending.next() {
                    group.addTask { await Self.load(next, client) }
                }
            }
            return results
        }
    }

    private static func load(_ ref: PRRef, _ client: GitHubClient) async -> (PRRef, Result<PRDetail, Error>) {
        do {
            return (ref, .success(try await client.pullRequest(ref)))
        } catch {
            return (ref, .failure(error))
        }
    }

    private func refreshCategories(client: GitHubClient, errors: inout [String]) async -> [CategoryResult] {
        let teammates = await resolveTeammates(client: client, errors: &errors)
        var results: [CategoryResult] = []
        for category in config.categories {
            guard let query = category.searchQuery(teammates: teammates, alsoExcluding: config.excludeRepos) else {
                results.append(CategoryResult(name: category.name, count: 0, prs: [], note: "Add teammates in the config when you want this category."))
                continue
            }
            do {
                let (total, found) = try await client.searchPullRequests(query)
                let prs = Self.markSkipped(found, labels: config.skipLabels)
                var count = total - prs.filter(\.isSkipped).count
                // The search returns 50 PRs at most. Past that, ask GitHub for the count without the skip labels.
                if total > found.count && !config.skipLabels.isEmpty {
                    let excluding = config.skipLabels.map { "-label:\"\($0)\"" }.joined(separator: " ")
                    count = try await client.searchPullRequests(query + " " + excluding).count
                }
                results.append(CategoryResult(name: category.name, count: count, prs: prs))
            } catch {
                errors.append("\(category.name): \(error.localizedDescription)")
                results.append(CategoryResult(name: category.name, count: 0, prs: [], note: error.localizedDescription))
            }
        }
        return results
    }

    private func refreshMine(client: GitHubClient, errors: inout [String]) async -> [CategoryResult] {
        guard !config.myPRGroups.isEmpty else { return [] }
        do {
            let (_, prs) = try await client.searchPullRequests("is:pr is:open author:@me archived:false sort:updated-desc")
            return PRGroup.assign(prs, to: config.myPRGroups)
        } catch {
            errors.append("My PRs: \(error.localizedDescription)")
            return []
        }
    }

    /// The 100 most recently updated merged PRs, then ordered by merge date.
    /// GitHub search has no merge-date sort, so the page is `sort:updated-desc` and the order is applied here.
    private func refreshMerged(client: GitHubClient, errors: inout [String]) async -> [ReviewPR] {
        do {
            let (_, prs) = try await client.searchPullRequests(
                "is:pr is:merged author:@me archived:false sort:updated-desc",
                first: 100
            )
            return MergedPRs.byDate(prs)
        } catch {
            errors.append("Merged PRs: \(error.localizedDescription)")
            return []
        }
    }

    /// Sets `skipLabels` on each PR and moves skipped PRs to the end, keeping GitHub's order otherwise.
    static func markSkipped(_ prs: [ReviewPR], labels: [String]) -> [ReviewPR] {
        let wanted = Set(labels.map { $0.lowercased() })
        let marked = prs.map { pr -> ReviewPR in
            var pr = pr
            pr.skipLabels = pr.labels.filter { wanted.contains($0.name.lowercased()) }
            return pr
        }
        return marked.filter { !$0.isSkipped } + marked.filter(\.isSkipped)
    }

    /// How many PRs a category would match, for the filters editor. nil when it can't be run.
    public func matchCount(_ category: Category, globalExcludes: [String]) async throws -> Int? {
        guard let client else { return nil }
        var errors: [String] = []
        let teammates = await resolveTeammates(client: client, errors: &errors)
        guard let query = category.searchQuery(teammates: teammates, alsoExcluding: globalExcludes) else { return nil }
        return try await client.searchPullRequests(query).count
    }

    private func resolveTeammates(client: GitHubClient, errors: inout [String]) async -> [String] {
        var logins = config.teammates
        if let team = config.teammatesTeam {
            if let cache = teamMembersCache, cache.team == team, cache.fetchedAt.timeIntervalSinceNow > -3600 {
                logins += cache.logins
            } else {
                do {
                    let members = try await client.teamMembers(team)
                    teamMembersCache = (team, members, Date())
                    logins += members
                } catch {
                    errors.append("teammatesTeam: \(error.localizedDescription)")
                }
            }
        }
        let skip = Set(([me ?? ""] + config.ignoredUsers).map { $0.lowercased() })
        var seen = Set<String>()
        return logins.filter { !skip.contains($0.lowercased()) && seen.insert($0.lowercased()).inserted }
    }

    /// Marks items read locally, and on GitHub for PRs with nothing unread left.
    public func markRead(_ ids: Set<String>) async {
        var touched = Set<String>()
        for i in state.items.indices where ids.contains(state.items[i].id) {
            state.items[i].read = true
            touched.insert(state.items[i].pr.key)
        }
        save()
        guard let client else { return }
        for key in touched where !state.items.contains(where: { $0.pr.key == key && !$0.read }) {
            if let threadId = state.threadIds[key] {
                try? await client.markThreadRead(threadId)
            }
        }
    }
}
