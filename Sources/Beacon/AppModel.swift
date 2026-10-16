import AppKit
import Core
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var items: [FeedItem] = []
    /// Review categories with single hidden PRs taken out, and their counts lowered to match.
    @Published private(set) var categories: [CategoryResult] = []
    /// Review categories as GitHub returned them.
    private var allCategories: [CategoryResult] = []
    /// PRs hidden one at a time from Reviews, by id, with a label for the menu that brings them back.
    /// Kept on this Mac only, apart from the config's repo filters.
    @Published private(set) var hiddenPRs = UserDefaults.standard.dictionary(forKey: "hiddenPRs") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(hiddenPRs, forKey: "hiddenPRs") }
    }
    /// Your own open PRs by `myPRGroups`. Only shown in the panel, never in the menu bar.
    @Published private(set) var mine: [CategoryResult] = []
    @Published private(set) var errors: [String] = []

    #if DEBUG
    /// Shows the sign-in panel for one error string. Release builds have no such hook.
    func previewSignInError(_ message: String) {
        errors = [message]
    }

    /// Same text `TokenProvider` throws when `gh` is not on this Mac.
    func previewMissingGitHubCLI() {
        previewSignInError("gh not found. Install it with `brew install gh` and run `gh auth login`.")
    }
    #endif

    /// gh is missing, or GitHub rejected the token. The panel shows the sign-in steps.
    var needsSignIn: Bool {
        errors.contains { message in
            message.contains("gh not found")
                || message.contains("gh auth token")
                || message.contains("GitHub 401")
        }
    }
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    /// Notifications tab shows read items too. Reset every time the panel opens.
    @Published var showRead = false
    /// Bumped each time the panel opens, so its content rebuilds and plays its entrance.
    @Published private(set) var panelOpens = 0
    /// Repos folded in the Mine tab. Remembered across launches.
    @Published private(set) var collapsedRepos = Set(UserDefaults.standard.stringArray(forKey: "collapsedRepos") ?? []) {
        didSet { UserDefaults.standard.set(collapsedRepos.sorted(), forKey: "collapsedRepos") }
    }

    private let engine = FeedEngine()
    private var loop: Task<Void, Never>?

    var config: Config { engine.config }
    var unreadCount: Int { items.filter { !$0.read }.count }
    var mineCount: Int { mine.reduce(0) { $0 + $1.count } }

    /// Count from the first badge level with open PRs, and whether that level is dimmed.
    var reviewBadge: (count: Int, dim: Bool) {
        for level in config.badgeChain {
            if let category = categories.first(where: { $0.name == level.category }), category.count > 0 {
                return (category.count, level.dim ?? false)
            }
        }
        return (0, false)
    }

    init() {
        items = engine.state.items
    }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.engine.pollInterval))
            }
        }
    }

    private var refreshAgain = false

    func refresh() async {
        // A config edit during a refresh still needs its own pass afterwards.
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        isRefreshing = true
        await runRefresh()
        isRefreshing = false
        if refreshAgain {
            refreshAgain = false
            await refresh()
        }
    }

    private func runRefresh() async {
        do {
            let snapshot = try await engine.refresh()
            items = engine.state.items
            allCategories = snapshot.categories
            forgetGoneHiddenPRs(errors: snapshot.errors)
            applyHiddenPRs()
            mine = snapshot.mine
            errors = snapshot.errors
            lastUpdated = Date()
            if !snapshot.isFirstRun && config.systemNotifications {
                postSystemNotifications(snapshot.newItems)
            }
        } catch {
            errors = [error.localizedDescription]
        }
    }

    /// Called when the panel opens. A refresh already under way covers it, so this doesn't queue another.
    func refreshOnOpen() {
        guard !isRefreshing else { return }
        Task { await refresh() }
    }

    func open(_ item: FeedItem) {
        if let url = URL(string: item.url) { NSWorkspace.shared.open(url) }
        markRead([item.id])
    }

    func open(itemId: String) {
        if let item = items.first(where: { $0.id == itemId }) { open(item) }
    }

    func open(_ pr: ReviewPR) {
        if let url = URL(string: pr.url) { NSWorkspace.shared.open(url) }
    }

    func panelWillOpen() {
        showRead = false
        panelOpens += 1
    }

    func toggleCollapsed(_ repo: String) {
        if collapsedRepos.contains(repo) { collapsedRepos.remove(repo) } else { collapsedRepos.insert(repo) }
    }

    /// Marks one item read without opening it.
    func markRead(_ item: FeedItem) {
        markRead([item.id])
    }

    func markAllRead() {
        markRead(Set(items.filter { !$0.read }.map(\.id)))
    }

    private func markRead(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for i in items.indices where ids.contains(items[i].id) { items[i].read = true }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(ids))
        Task { await engine.markRead(ids) }
    }

    /// Repos seen in the review queue or the feed, plus any already used in a filter.
    var knownRepos: [String] {
        var repos = Set(categories.flatMap { $0.prs.map(\.repo) })
        repos.formUnion(items.map(\.pr.repo))
        repos.formUnion(config.excludeRepos)
        for category in config.categories {
            repos.formUnion(category.includeRepos)
            repos.formUnion(category.excludeRepos)
        }
        return repos.sorted()
    }

    /// Hides a repo from one category, or from all of them when `category` is nil.
    func hide(repo: String, from category: String?) {
        for i in allCategories.indices where category == nil || allCategories[i].name == category {
            let removed = allCategories[i].prs.filter { $0.repo == repo && !$0.isSkipped }.count
            allCategories[i].prs.removeAll { $0.repo == repo }
            allCategories[i].count -= removed
        }
        applyHiddenPRs()
        editConfig { config in
            if let category {
                if let i = config.categories.firstIndex(where: { $0.name == category }), !config.categories[i].excludeRepos.contains(repo) {
                    config.categories[i].excludeRepos.append(repo)
                }
            } else if !config.excludeRepos.contains(repo) {
                config.excludeRepos.append(repo)
            }
        }
    }

    /// Hides one PR from every review category without touching the filters.
    func hide(pr: ReviewPR) {
        hiddenPRs[pr.id] = "\(pr.repoName)#\(pr.number) \(pr.title)"
        applyHiddenPRs()
    }

    func unhide(prId: String) {
        hiddenPRs[prId] = nil
        applyHiddenPRs()
    }

    /// Hidden PRs that GitHub still lists in a category, for that section's menu.
    func hiddenPRs(in category: String) -> [(id: String, label: String)] {
        let prs = allCategories.first { $0.name == category }?.prs ?? []
        return prs.compactMap { pr in hiddenPRs[pr.id].map { (pr.id, $0) } }
    }

    private func applyHiddenPRs() {
        categories = allCategories.map { category in
            var category = category
            let hidden = category.prs.filter { hiddenPRs[$0.id] != nil }
            category.prs.removeAll { hiddenPRs[$0.id] != nil }
            category.count = max(0, category.count - hidden.filter { !$0.isSkipped }.count)
            return category
        }
    }

    /// Drops hidden PRs no category lists anymore (merged, closed, or reviewed), so a PR that comes back
    /// later, like a new review request, shows again. Skipped when a search failed or was cut off at 50.
    private func forgetGoneHiddenPRs(errors: [String]) {
        guard errors.isEmpty, allCategories.allSatisfy({ $0.prs.count >= $0.count }) else { return }
        let listed = Set(allCategories.flatMap { $0.prs.map(\.id) })
        let kept = hiddenPRs.filter { listed.contains($0.key) }
        if kept.count != hiddenPRs.count { hiddenPRs = kept }
    }

    func unhide(repo: String, from category: String?) {
        editConfig { config in
            if let category {
                if let i = config.categories.firstIndex(where: { $0.name == category }) {
                    config.categories[i].excludeRepos.removeAll { $0 == repo }
                }
            } else {
                config.excludeRepos.removeAll { $0 == repo }
            }
        }
    }

    /// Reads the config from disk, applies `change`, saves it and refreshes.
    func editConfig(_ change: (inout Config) -> Void) {
        do {
            var config = try ConfigStore.load()
            change(&config)
            try ConfigStore.save(config)
        } catch {
            errors = [error.localizedDescription]
            return
        }
        Task { await refresh() }
    }

    func matchCount(_ category: Core.Category, globalExcludes: [String]) async -> Int? {
        try? await engine.matchCount(category, globalExcludes: globalExcludes)
    }

    func openConfig() {
        _ = try? ConfigStore.load()
        NSWorkspace.shared.open(ConfigStore.url)
    }

    #if DEBUG
    /// Fills the panel for `--snapshot` without polling GitHub.
    func loadPreview(
        items: [FeedItem],
        categories: [CategoryResult],
        mine: [CategoryResult],
        errors: [String] = [],
        lastUpdated: Date? = Date()
    ) {
        self.items = items
        allCategories = categories
        applyHiddenPRs()
        self.mine = mine
        self.errors = errors
        self.lastUpdated = lastUpdated
        isRefreshing = false
        panelOpens = 1
    }
    #endif

    private func postSystemNotifications(_ newItems: [FeedItem]) {
        let center = UNUserNotificationCenter.current()
        // After a long sleep, one summary beats a wall of banners.
        if newItems.count > 3 {
            let content = UNMutableNotificationContent()
            content.title = "\(newItems.count) new GitHub notifications"
            content.body = newItems.prefix(3).map { "\($0.actor) \($0.verb) \($0.pr.name)#\($0.pr.number)" }.joined(separator: "\n")
            center.add(UNNotificationRequest(identifier: "summary-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
            return
        }
        for item in newItems {
            let content = UNMutableNotificationContent()
            content.title = "\(item.actor) \(item.verb) \(item.pr.name)#\(item.pr.number)"
            content.subtitle = item.prTitle
            content.body = item.snippet
            content.sound = .default
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: nil))
        }
    }
}
