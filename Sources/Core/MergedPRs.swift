import Foundation

/// Orders your merged pull requests for the Merged section.
public enum MergedPRs {
    /// Newest merge first. A pull request with no merge date goes last.
    /// The same merge date keeps a stable order by id.
    public static func byDate(_ prs: [ReviewPR]) -> [ReviewPR] {
        prs.sorted { a, b in
            switch (a.mergedAt, b.mergedAt) {
            case let (left?, right?):
                if left != right { return left > right }
                return a.id < b.id
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return a.id < b.id
            }
        }
    }

    public struct RepoGroup: Identifiable, Equatable {
        public var repo: String
        /// Newest merge first.
        public var prs: [ReviewPR]
        public var id: String { repo }
    }

    /// Repositories with the newest merge first. Pull requests inside each repository, newest merge first.
    public static func byRepo(_ prs: [ReviewPR]) -> [RepoGroup] {
        var order: [String] = []
        var grouped: [String: [ReviewPR]] = [:]
        for pr in byDate(prs) {
            if grouped[pr.repo] == nil { order.append(pr.repo) }
            grouped[pr.repo, default: []].append(pr)
        }
        return order.map { RepoGroup(repo: $0, prs: grouped[$0] ?? []) }
    }
}
