import Foundation

public struct ClassifierContext {
    public var me: String
    /// Teams whose @-mentions count, as `org/slug`.
    public var teams: [String]
    /// Lowercased logins whose activity is ignored.
    public var ignoredUsers: Set<String>
    public var ignoreBots: Bool
    public var approvalsWithComments: Bool

    public init(me: String, teams: [String] = [], ignoredUsers: Set<String> = [], ignoreBots: Bool = true, approvalsWithComments: Bool = true) {
        self.me = me
        self.teams = teams
        self.ignoredUsers = ignoredUsers
        self.ignoreBots = ignoreBots
        self.approvalsWithComments = approvalsWithComments
    }
}

/// Turns a PR's comments and reviews into feed items. Rules:
/// - mentions of me or one of my teams always count
/// - a new comment in an inline thread I wrote in is a reply
/// - on my PR: comments, change requests and reviews with a body count; bare approvals don't
/// - on someone else's PR: activity counts only after I first commented there
public enum Classifier {
    private enum Source {
        case comment
        case review(state: String)
        case thread(iCommentedEarlier: Bool)
    }

    public static func classify(_ pr: PRDetail, since: Date, context ctx: ClassifierContext) -> [FeedItem] {
        let me = ctx.me.lowercased()
        func isMe(_ author: Author?) -> Bool { author?.login.lowercased() == me }

        let isMyPR = isMe(pr.author)
        // Only things I wrote count as taking part. A bare approval isn't something anyone replies to.
        let myActivity = pr.comments.filter { isMe($0.author) }.map(\.createdAt)
            + pr.reviews.filter { isMe($0.author) && (hasText($0.body) || $0.state == "CHANGES_REQUESTED") }.compactMap(\.submittedAt)
            + pr.threads.joined().filter { isMe($0.author) }.map(\.createdAt)
        let firstActivity = myActivity.min()

        var items: [FeedItem] = []

        func consider(id: String, author: Author?, body: String, date: Date, url: String, source: Source) {
            guard date > since, let author, !isMe(author) else { return }
            if ctx.ignoreBots && author.isBot { return }
            if ctx.ignoredUsers.contains(author.login.lowercased()) { return }

            let participated = isMyPR || (firstActivity.map { $0 < date } ?? false)
            guard let (kind, team) = kind(body: body, source: source, isMyPR: isMyPR, participated: participated, ctx: ctx) else { return }

            var snippet = snippetText(body)
            if snippet.isEmpty && kind == .changesRequested { snippet = "Requested changes" }
            items.append(FeedItem(
                id: id, kind: kind, team: team, actor: author.login, pr: pr.ref,
                prTitle: pr.title, prState: pr.state, onMyPR: isMyPR,
                snippet: snippet, url: url, createdAt: date
            ))
        }

        for c in pr.comments {
            consider(id: c.id, author: c.author, body: c.body, date: c.createdAt, url: c.url, source: .comment)
        }
        for r in pr.reviews {
            guard let date = r.submittedAt else { continue }
            consider(id: r.id, author: r.author, body: r.body, date: date, url: r.url, source: .review(state: r.state))
        }
        for thread in pr.threads {
            for c in thread {
                let mineEarlier = thread.contains { isMe($0.author) && $0.createdAt < c.createdAt }
                consider(id: c.id, author: c.author, body: c.body, date: c.createdAt, url: c.url, source: .thread(iCommentedEarlier: mineEarlier))
            }
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    private static func kind(body: String, source: Source, isMyPR: Bool, participated: Bool, ctx: ClassifierContext) -> (FeedKind, String?)? {
        let unquoted = stripQuotes(body)
        if mentions(unquoted, ctx.me) { return (.mention, nil) }
        if let team = ctx.teams.first(where: { mentions(unquoted, $0) }) { return (.teamMention, team) }
        if case .thread(true) = source { return (.reply, nil) }
        guard participated else { return nil }
        // On someone else's PR, a comment that @-mentions other people is addressed to them.
        if !isMyPR && mentionsAnyone(unquoted) { return nil }

        let hasBody = hasText(body)
        switch source {
        case .review(let state):
            switch state {
            case "CHANGES_REQUESTED": return (.changesRequested, nil)
            case "APPROVED": return hasBody && ctx.approvalsWithComments ? (.approvedWithComment, nil) : nil
            // An empty COMMENTED review is the wrapper around inline comments, which show up as threads.
            // DISMISSED is the current state; the review may have been an approval or comment with text.
            case "COMMENTED", "DISMISSED": return hasBody ? (.reviewed, nil) : nil
            default: return nil
            }
        case .comment, .thread:
            return (.comment, nil)
        }
    }

    static func mentions(_ text: String, _ handle: String) -> Bool {
        let pattern = "(?<![A-Za-z0-9_/@-])@" + NSRegularExpression.escapedPattern(for: handle) + "(?![A-Za-z0-9_/-])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func mentionsAnyone(_ text: String) -> Bool {
        text.range(of: "(?<![A-Za-z0-9_/@-])@[A-Za-z0-9][A-Za-z0-9-]*", options: .regularExpression) != nil
    }

    private static func hasText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Drops markdown quote lines, so quoting a comment that mentions me isn't a new mention.
    static func stripQuotes(_ text: String) -> String {
        // components(separatedBy: .newlines) splits "\r\n", which Swift treats as one Character.
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
            .joined(separator: "\n")
    }

    static func snippetText(_ text: String) -> String {
        let withoutHTMLComments = text
            .replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<img[^>]*>|!\\[[^\\]]*\\]\\([^)]*\\)", with: "[image]", options: .regularExpression)
            .replacingOccurrences(of: "</?[a-zA-Z][^>]*>", with: "", options: .regularExpression)
        func collapse(_ s: String) -> String {
            s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        }
        var collapsed = collapse(stripQuotes(withoutHTMLComments))
        // A comment that is only a quote still says something, so show the quote.
        if collapsed.isEmpty {
            collapsed = collapse(withoutHTMLComments.replacingOccurrences(of: "(?m)^\\s*>\\s?", with: "", options: .regularExpression))
        }
        return collapsed.count > 240 ? String(collapsed.prefix(240)) + "…" : collapsed
    }
}
