import Foundation

public struct PRRef: Hashable, Codable {
    public var owner: String
    public var name: String
    public var number: Int

    public init(owner: String, name: String, number: Int) {
        self.owner = owner
        self.name = name
        self.number = number
    }

    /// Parses `https://api.github.com/repos/{owner}/{name}/pulls/{number}`.
    public init?(apiURL: String?) {
        guard let apiURL, let url = URL(string: apiURL) else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 6, parts[1] == "repos", parts[4] == "pulls", let number = Int(parts[5]) else { return nil }
        self.init(owner: parts[2], name: parts[3], number: number)
    }

    public var repo: String { "\(owner)/\(name)" }
    public var key: String { "\(repo)#\(number)" }
    public var webURL: URL? { URL(string: "https://github.com/\(repo)/pull/\(number)") }
}

public struct Author: Hashable {
    public var login: String
    public var isBot: Bool

    public init(login: String, isBot: Bool = false) {
        self.login = login
        self.isBot = isBot
    }
}

public struct PRComment {
    public var id: String
    public var author: Author?
    public var body: String
    public var createdAt: Date
    public var url: String

    public init(id: String, author: Author?, body: String, createdAt: Date, url: String) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.url = url
    }
}

public struct PRReview {
    public var id: String
    public var author: Author?
    /// APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED or PENDING.
    public var state: String
    public var body: String
    public var submittedAt: Date?
    public var url: String

    public init(id: String, author: Author?, state: String, body: String, submittedAt: Date?, url: String) {
        self.id = id
        self.author = author
        self.state = state
        self.body = body
        self.submittedAt = submittedAt
        self.url = url
    }
}

public struct PRDetail {
    public var ref: PRRef
    public var title: String
    public var url: String
    /// OPEN, CLOSED or MERGED.
    public var state: String
    public var author: Author?
    /// Comments on the conversation tab.
    public var comments: [PRComment]
    public var reviews: [PRReview]
    /// Inline review threads, each in chronological order.
    public var threads: [[PRComment]]

    public init(ref: PRRef, title: String, url: String, state: String, author: Author?, comments: [PRComment] = [], reviews: [PRReview] = [], threads: [[PRComment]] = []) {
        self.ref = ref
        self.title = title
        self.url = url
        self.state = state
        self.author = author
        self.comments = comments
        self.reviews = reviews
        self.threads = threads
    }
}

public enum FeedKind: String, Codable {
    case mention
    case teamMention
    case reply
    case changesRequested
    case approvedWithComment
    case reviewed
    case comment
}

public struct FeedItem: Codable, Identifiable, Hashable {
    public var id: String
    public var kind: FeedKind
    /// Team slug for `teamMention`.
    public var team: String?
    public var actor: String
    public var pr: PRRef
    public var prTitle: String
    public var prState: String
    public var onMyPR: Bool
    public var snippet: String
    public var url: String
    public var createdAt: Date
    public var read: Bool

    public init(id: String, kind: FeedKind, team: String? = nil, actor: String, pr: PRRef, prTitle: String, prState: String, onMyPR: Bool, snippet: String, url: String, createdAt: Date, read: Bool = false) {
        self.id = id
        self.kind = kind
        self.team = team
        self.actor = actor
        self.pr = pr
        self.prTitle = prTitle
        self.prState = prState
        self.onMyPR = onMyPR
        self.snippet = snippet
        self.url = url
        self.createdAt = createdAt
        self.read = read
    }

    public var verb: String {
        switch kind {
        case .mention: return "mentioned you on"
        case .teamMention: return "mentioned @\(team ?? "your team") on"
        case .reply: return "replied to your comment on"
        case .changesRequested: return "requested changes on"
        case .approvedWithComment: return "approved with a comment"
        case .reviewed: return "reviewed"
        case .comment: return "commented on"
        }
    }

    public var isClosed: Bool { prState != "OPEN" }
}

/// Feed items on one pull request, newest first.
public struct PRThread: Identifiable, Hashable {
    public var pr: PRRef
    public var items: [FeedItem]

    public var id: String { pr.key }
    /// The newest item has the latest title and state.
    public var title: String { items[0].prTitle }
    public var prState: String { items[0].prState }
    public var isClosed: Bool { items[0].isClosed }
    public var latest: Date { items[0].createdAt }
    public var unreadCount: Int { items.filter { !$0.read }.count }

    /// One thread per pull request, the one with the newest activity first.
    public static func group(_ items: [FeedItem]) -> [PRThread] {
        let byPR = Dictionary(grouping: items, by: \.pr)
        return byPR.map { pr, items in
            PRThread(pr: pr, items: items.sorted { $0.createdAt > $1.createdAt })
        }
        .sorted { $0.latest != $1.latest ? $0.latest > $1.latest : $0.id < $1.id }
    }
}

public struct PRLabel: Hashable {
    public var name: String
    /// Hex color without "#", as GitHub returns it.
    public var color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

public struct ReviewPR: Identifiable, Hashable {
    public var id: String
    public var repo: String
    public var number: Int
    public var title: String
    public var url: String
    public var author: String
    public var createdAt: Date
    /// SUCCESS, FAILURE, ERROR, PENDING, EXPECTED, or nil when the PR has no checks.
    public var ciState: String?
    public var labels: [PRLabel] = []
    /// Labels that keep this PR out of the counts, e.g. "DO NOT REVIEW".
    public var skipLabels: [PRLabel] = []
    public var isDraft = false
    /// APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, or nil when the repo doesn't require reviews.
    public var reviewDecision: String?

    public init(
        id: String,
        repo: String,
        number: Int,
        title: String,
        url: String,
        author: String,
        createdAt: Date,
        ciState: String?,
        labels: [PRLabel] = [],
        skipLabels: [PRLabel] = [],
        isDraft: Bool = false,
        reviewDecision: String? = nil
    ) {
        self.id = id
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.author = author
        self.createdAt = createdAt
        self.ciState = ciState
        self.labels = labels
        self.skipLabels = skipLabels
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
    }

    public var isSkipped: Bool { !skipLabels.isEmpty }

    public var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }
}

public struct CategoryResult: Identifiable {
    public var name: String
    /// Open PRs that need a review. Skipped PRs are listed but not counted.
    public var count: Int
    public var prs: [ReviewPR]
    /// Set when the category was skipped, e.g. `{teammates}` with no teammates configured.
    public var note: String?

    public var id: String { name }

    public init(name: String, count: Int, prs: [ReviewPR], note: String? = nil) {
        self.name = name
        self.count = count
        self.prs = prs
        self.note = note
    }
}
