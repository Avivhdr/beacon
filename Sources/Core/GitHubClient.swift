import Foundation

public struct NotificationThread: Decodable {
    public struct Subject: Decodable {
        public var title: String
        public var url: String?
        public var type: String
    }

    public var id: String
    public var reason: String
    public var unread: Bool
    public var updatedAt: Date
    public var lastReadAt: Date?
    public var subject: Subject

    enum CodingKeys: String, CodingKey {
        case id, reason, unread, subject
        case updatedAt = "updated_at"
        case lastReadAt = "last_read_at"
    }
}

public struct NotificationsPage {
    public var threads: [NotificationThread]
    public var lastModified: String?
    public var pollInterval: Int?
    public var notModified: Bool
}

public final class GitHubClient {
    private let token: String
    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(token: String) {
        self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    // MARK: REST

    @discardableResult
    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], headers: [String: String] = [:], body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(string: "https://api.github.com" + path)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AppError("No HTTP response from \(path)") }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 304 else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw AppError("GitHub \(http.statusCode) on \(path): \(message ?? "unknown error")")
        }
        return (data, http)
    }

    public func viewerLogin() async throws -> String {
        struct User: Decodable { var login: String }
        let (data, _) = try await request("/user")
        return try decoder.decode(User.self, from: data).login
    }

    /// Teams the viewer belongs to, as `org/slug`.
    public func myTeams() async throws -> [String] {
        struct Team: Decodable {
            struct Org: Decodable { var login: String }
            var slug: String
            var organization: Org
        }
        let (data, _) = try await request("/user/teams", query: [URLQueryItem(name: "per_page", value: "100")])
        return try decoder.decode([Team].self, from: data).map { "\($0.organization.login)/\($0.slug)" }
    }

    public func teamMembers(_ team: String) async throws -> [String] {
        struct Member: Decodable { var login: String }
        let parts = team.split(separator: "/")
        guard parts.count == 2 else { throw AppError("teammatesTeam must look like org/slug, got \(team)") }
        var logins: [String] = []
        for page in 1...10 {
            let (data, _) = try await request("/orgs/\(parts[0])/teams/\(parts[1])/members", query: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: "\(page)"),
            ])
            let members = try decoder.decode([Member].self, from: data)
            logins += members.map(\.login)
            if members.count < 100 { break }
        }
        return logins
    }

    /// Participating notifications (read and unread) updated after `since`.
    public func notifications(since: Date, ifModifiedSince: String?) async throws -> NotificationsPage {
        var threads: [NotificationThread] = []
        var lastModified: String?
        var pollInterval: Int?
        let sinceString = ISO8601DateFormatter().string(from: since)
        for page in 1...10 {
            let headers = page == 1 ? ifModifiedSince.map { ["If-Modified-Since": $0] } ?? [:] : [:]
            let (data, http) = try await request("/notifications", query: [
                URLQueryItem(name: "all", value: "true"),
                URLQueryItem(name: "participating", value: "true"),
                URLQueryItem(name: "since", value: sinceString),
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "page", value: "\(page)"),
            ], headers: headers)
            if page == 1 {
                if http.statusCode == 304 { return NotificationsPage(threads: [], lastModified: ifModifiedSince, pollInterval: nil, notModified: true) }
                lastModified = http.value(forHTTPHeaderField: "Last-Modified")
                pollInterval = http.value(forHTTPHeaderField: "X-Poll-Interval").flatMap(Int.init)
            }
            let batch = try decoder.decode([NotificationThread].self, from: data)
            threads += batch
            if batch.count < 50 { break }
        }
        return NotificationsPage(threads: threads, lastModified: lastModified, pollInterval: pollInterval, notModified: false)
    }

    public func markThreadRead(_ id: String) async throws {
        try await request("/notifications/threads/\(id)", method: "PATCH")
    }

    // MARK: GraphQL

    private struct GraphQLResponse<T: Decodable>: Decodable {
        struct GraphQLError: Decodable { var message: String }
        var data: T?
        var errors: [GraphQLError]?
    }

    /// Returns data even when GitHub also reports partial errors (e.g. one repo blocked by SSO).
    private func graphql<T: Decodable>(_ query: String, _ variables: [String: Any], as: T.Type) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, _) = try await request("/graphql", method: "POST", body: body)
        let response = try decoder.decode(GraphQLResponse<T>.self, from: data)
        guard let result = response.data else {
            throw AppError("GraphQL: " + (response.errors?.map(\.message).joined(separator: "; ") ?? "no data"))
        }
        return result
    }

    private struct GQLActor: Decodable {
        var login: String
        var typename: String
        enum CodingKeys: String, CodingKey { case login, typename = "__typename" }
        var author: Author { Author(login: login, isBot: typename == "Bot" || login.hasSuffix("[bot]")) }
    }

    private struct Nodes<T: Decodable>: Decodable { var nodes: [T?] }

    private struct GQLComment: Decodable {
        var id: String
        var author: GQLActor?
        var body: String
        var createdAt: Date
        var url: String
        var comment: PRComment { PRComment(id: id, author: author?.author, body: body, createdAt: createdAt, url: url) }
    }

    private static let pullRequestQuery = """
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          title url state
          author { login __typename }
          comments(last: 100) { nodes { id author { login __typename } body createdAt url } }
          reviews(last: 100) { nodes { id state author { login __typename } body submittedAt url } }
          reviewThreads(last: 100) {
            nodes { comments(first: 100) { nodes { id author { login __typename } body createdAt url } } }
          }
        }
      }
    }
    """

    public func pullRequest(_ ref: PRRef) async throws -> PRDetail {
        struct Review: Decodable {
            var id: String
            var state: String
            var author: GQLActor?
            var body: String
            var submittedAt: Date?
            var url: String
        }
        struct Thread: Decodable { var comments: Nodes<GQLComment> }
        struct PR: Decodable {
            var title: String
            var url: String
            var state: String
            var author: GQLActor?
            var comments: Nodes<GQLComment>
            var reviews: Nodes<Review>
            var reviewThreads: Nodes<Thread>
        }
        struct Repo: Decodable { var pullRequest: PR? }
        struct Response: Decodable { var repository: Repo? }

        let response = try await graphql(Self.pullRequestQuery, ["owner": ref.owner, "name": ref.name, "number": ref.number], as: Response.self)
        guard let pr = response.repository?.pullRequest else { throw AppError("Can't load \(ref.key)") }
        return PRDetail(
            ref: ref, title: pr.title, url: pr.url, state: pr.state, author: pr.author?.author,
            comments: pr.comments.nodes.compactMap { $0?.comment },
            reviews: pr.reviews.nodes.compactMap { $0 }.map {
                PRReview(id: $0.id, author: $0.author?.author, state: $0.state, body: $0.body, submittedAt: $0.submittedAt, url: $0.url)
            },
            threads: pr.reviewThreads.nodes.compactMap { $0?.comments.nodes.compactMap { $0?.comment } }
        )
    }

    private static let searchQuery = """
    query($q: String!, $first: Int!) {
      search(query: $q, type: ISSUE, first: $first) {
        issueCount
        nodes {
          ... on PullRequest {
            id number title url createdAt mergedAt isDraft reviewDecision
            author { login }
            repository { nameWithOwner }
            labels(first: 20) { nodes { name color } }
            commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
          }
        }
      }
    }
    """

    /// `first` is one search page. GitHub allows at most 100.
    public func searchPullRequests(_ query: String, first: Int = 50) async throws -> (count: Int, prs: [ReviewPR]) {
        struct Login: Decodable { var login: String }
        struct Repo: Decodable { var nameWithOwner: String }
        struct Label: Decodable { var name: String; var color: String }
        struct Rollup: Decodable { var state: String }
        struct Commit: Decodable { var statusCheckRollup: Rollup? }
        struct CommitNode: Decodable { var commit: Commit }
        struct Node: Decodable {
            var id: String?
            var number: Int?
            var title: String?
            var url: String?
            var createdAt: Date?
            var mergedAt: Date?
            var isDraft: Bool?
            var reviewDecision: String?
            var author: Login?
            var repository: Repo?
            var labels: Nodes<Label>?
            var commits: Nodes<CommitNode>?
        }
        struct Search: Decodable {
            var issueCount: Int
            var nodes: [Node?]
        }
        struct Response: Decodable { var search: Search }

        let page = min(max(first, 1), 100)
        let search = try await graphql(Self.searchQuery, ["q": query, "first": page], as: Response.self).search
        let prs = search.nodes.compactMap { node -> ReviewPR? in
            guard let node, let id = node.id, let number = node.number, let title = node.title,
                  let url = node.url, let createdAt = node.createdAt, let repo = node.repository else { return nil }
            return ReviewPR(
                id: id, repo: repo.nameWithOwner, number: number, title: title, url: url,
                author: node.author?.login ?? "ghost", createdAt: createdAt,
                ciState: node.commits?.nodes.first??.commit.statusCheckRollup?.state,
                labels: node.labels?.nodes.compactMap { $0.map { PRLabel(name: $0.name, color: $0.color) } } ?? [],
                isDraft: node.isDraft ?? false,
                reviewDecision: node.reviewDecision,
                mergedAt: node.mergedAt
            )
        }
        return (search.issueCount, prs)
    }
}
