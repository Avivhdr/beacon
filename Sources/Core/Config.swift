import Foundation

public struct Category: Codable, Hashable, Identifiable {
    /// Only lives in memory, so the filters editor can track a category across renames.
    public var id = UUID()
    public var name: String
    /// GitHub search query. `{teammates}` expands to `author:` qualifiers for every teammate.
    public var query: String
    /// When set, only PRs from these repos (`org/name`).
    public var includeRepos: [String] = []
    public var excludeRepos: [String] = []

    enum CodingKeys: String, CodingKey { case name, query, includeRepos, excludeRepos }

    public init(name: String, query: String, includeRepos: [String] = [], excludeRepos: [String] = []) {
        self.name = name
        self.query = query
        self.includeRepos = includeRepos
        self.excludeRepos = excludeRepos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        query = try c.decode(String.self, forKey: .query)
        includeRepos = try c.decodeIfPresent([String].self, forKey: .includeRepos) ?? []
        excludeRepos = try c.decodeIfPresent([String].self, forKey: .excludeRepos) ?? []
    }

    public var usesTeammates: Bool { query.contains("{teammates}") }

    /// The query sent to GitHub. nil when it needs teammates and there are none.
    public func searchQuery(teammates: [String], alsoExcluding globalExcludes: [String] = []) -> String? {
        var query = query
        if usesTeammates {
            guard !teammates.isEmpty else { return nil }
            query = query.replacingOccurrences(of: "{teammates}", with: teammates.map { "author:\($0)" }.joined(separator: " "))
        }
        let excludes = (excludeRepos + globalExcludes).filter { !includeRepos.contains($0) }
        let parts = [query] + includeRepos.map { "repo:\($0)" } + Set(excludes).sorted().map { "-repo:\($0)" }
        return parts.joined(separator: " ")
    }

    public static let presets: [(label: String, query: String)] = [
        ("Requested from me directly", "is:pr is:open draft:false archived:false user-review-requested:@me"),
        ("Requested from one of my teams", "is:pr is:open draft:false archived:false review-requested:@me -user-review-requested:@me"),
        ("Requested from me or my teams", "is:pr is:open draft:false archived:false review-requested:@me"),
        ("Requested from me, written by teammates", "is:pr is:open draft:false archived:false review-requested:@me {teammates}"),
    ]
}

/// A layer in the Mine tab, like "Work" or "Private".
public struct PRGroup: Codable, Hashable {
    public var name: String
    /// `org/repo`, or a bare `org` for every repo it owns. Empty takes every PR the groups above it didn't.
    public var repos: [String] = []

    enum CodingKeys: String, CodingKey { case name, repos }

    public init(name: String, repos: [String] = []) {
        self.name = name
        self.repos = repos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        repos = try c.decodeIfPresent([String].self, forKey: .repos) ?? []
    }

    public func lists(_ repo: String) -> Bool {
        let repo = repo.lowercased()
        return repos.contains { entry in
            let entry = entry.lowercased()
            return entry.contains("/") ? entry == repo : repo.hasPrefix(entry + "/")
        }
    }

    /// Splits PRs into groups, keeping their order. A PR goes to the first group that lists its repo,
    /// otherwise to the first group with no repos. PRs that fit neither are left out.
    public static func assign(_ prs: [ReviewPR], to groups: [PRGroup]) -> [CategoryResult] {
        let catchAll = groups.firstIndex { $0.repos.isEmpty }
        var buckets = Array(repeating: [ReviewPR](), count: groups.count)
        for pr in prs {
            if let index = groups.firstIndex(where: { $0.lists(pr.repo) }) ?? catchAll {
                buckets[index].append(pr)
            }
        }
        return groups.indices.map { CategoryResult(name: groups[$0].name, count: buckets[$0].count, prs: buckets[$0]) }
    }
}

public struct BadgeLevel: Codable, Hashable {
    public var category: String
    public var dim: Bool?
}

public struct Config: Codable {
    public var pollIntervalSeconds = 60
    /// How far back to look on first launch.
    public var lookbackDays = 3
    public var ignoreBots = true
    public var ignoredUsers: [String] = []
    /// Teams whose mentions count, as `org/slug`. nil means every team you're in.
    public var mentionTeams: [String]?
    public var teammates: [String] = []
    /// `org/slug` of a GitHub team whose members are added to `teammates`.
    public var teammatesTeam: String?
    public var notifyApprovalsWithComments = true
    public var systemNotifications = true
    public var staleHours = 24
    /// PRs with any of these labels (any case) sit at the bottom of a category and aren't counted.
    public var skipLabels = ["DO NOT REVIEW"]
    /// Repos hidden from every category.
    public var excludeRepos: [String] = []
    public var categories: [Category] = [
        Category(name: "Direct", query: "is:pr is:open draft:false archived:false user-review-requested:@me"),
        Category(name: "Team", query: "is:pr is:open draft:false archived:false review-requested:@me -user-review-requested:@me"),
        Category(name: "Teammates", query: "is:pr is:open draft:false archived:false review-requested:@me {teammates}"),
    ]
    /// Layers of the Mine tab, which lists your own open PRs. Never counted in the menu bar.
    public var myPRGroups = [PRGroup(name: "Open")]
    /// The menu bar shows the count of the first level with open PRs.
    public var badgeChain: [BadgeLevel] = [
        BadgeLevel(category: "Direct", dim: false),
        BadgeLevel(category: "Team", dim: true),
    ]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        pollIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? d.pollIntervalSeconds
        lookbackDays = try c.decodeIfPresent(Int.self, forKey: .lookbackDays) ?? d.lookbackDays
        ignoreBots = try c.decodeIfPresent(Bool.self, forKey: .ignoreBots) ?? d.ignoreBots
        ignoredUsers = try c.decodeIfPresent([String].self, forKey: .ignoredUsers) ?? d.ignoredUsers
        mentionTeams = try c.decodeIfPresent([String].self, forKey: .mentionTeams)
        teammates = try c.decodeIfPresent([String].self, forKey: .teammates) ?? d.teammates
        teammatesTeam = try c.decodeIfPresent(String.self, forKey: .teammatesTeam)
        notifyApprovalsWithComments = try c.decodeIfPresent(Bool.self, forKey: .notifyApprovalsWithComments) ?? d.notifyApprovalsWithComments
        systemNotifications = try c.decodeIfPresent(Bool.self, forKey: .systemNotifications) ?? d.systemNotifications
        staleHours = try c.decodeIfPresent(Int.self, forKey: .staleHours) ?? d.staleHours
        skipLabels = try c.decodeIfPresent([String].self, forKey: .skipLabels) ?? d.skipLabels
        excludeRepos = try c.decodeIfPresent([String].self, forKey: .excludeRepos) ?? d.excludeRepos
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? d.categories
        badgeChain = try c.decodeIfPresent([BadgeLevel].self, forKey: .badgeChain) ?? d.badgeChain
        myPRGroups = try c.decodeIfPresent([PRGroup].self, forKey: .myPRGroups) ?? d.myPRGroups
    }
}

public enum ConfigStore {
    public static var url: URL { Paths.configURL }

    /// Loads the config, writing the defaults first if the file doesn't exist.
    public static func load() throws -> Config {
        Migration.migrateIfNeeded()
        if !FileManager.default.fileExists(atPath: url.path) {
            try save(Config())
        }
        do {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            throw AppError("Can't read \(url.path): \(error)")
        }
    }

    public static func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}

public struct AppError: LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum TokenProvider {
    /// Uses GITHUB_TOKEN if set, otherwise `gh auth token`.
    /// PATH is checked first so a login shell and a test can both choose which `gh` runs.
    public static func token() throws -> String {
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty { return token }
        guard let gh = ghExecutable(path: ProcessInfo.processInfo.environment["PATH"], isExecutable: FileManager.default.isExecutableFile(atPath:)) else {
            throw AppError("gh not found. Install it with `brew install gh` and run `gh auth login`.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["auth", "token", "--hostname", "github.com"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !token.isEmpty else {
            throw AppError("`gh auth token` failed. Run `gh auth login`.")
        }
        return token
    }

    /// `gh` on PATH, then the usual install locations.
    static func ghExecutable(path: String?, isExecutable: (String) -> Bool) -> String? {
        let onPath = (path ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent("gh").path }
        let candidates = onPath + ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        return candidates.first(where: isExecutable)
    }
}
