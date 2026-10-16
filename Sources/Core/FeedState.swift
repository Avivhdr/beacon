import Foundation

/// Everything persisted between launches.
public struct FeedState: Codable {
    public var items: [FeedItem] = []
    public var lastPoll: Date?
    public var lastModified: String?
    /// Per PR key, the time we last classified its activity.
    public var checkedAt: [String: Date] = [:]
    /// Per PR key, the GitHub notification thread id.
    public var threadIds: [String: String] = [:]

    public init() {}

    public var unreadCount: Int { items.filter { !$0.read }.count }

    /// Adds items not seen before and refreshes PR state on existing ones. Returns the new items.
    @discardableResult
    public mutating func merge(_ incoming: [FeedItem], for pr: PRDetail) -> [FeedItem] {
        for i in items.indices where items[i].pr == pr.ref {
            items[i].prState = pr.state
            items[i].prTitle = pr.title
        }
        let known = Set(items.map(\.id))
        let added = incoming.filter { !known.contains($0.id) }
        items += added
        items.sort { $0.createdAt > $1.createdAt }
        return added
    }

    /// Marks items read that GitHub says were read on github.com.
    public mutating func applyRemoteRead(pr: PRRef, lastReadAt: Date) {
        for i in items.indices where items[i].pr == pr && items[i].createdAt <= lastReadAt {
            items[i].read = true
        }
    }

    public mutating func prune(olderThan days: Int = 14, keep: Int = 300, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        items = Array(items.filter { $0.createdAt > cutoff }.prefix(keep))
        checkedAt = checkedAt.filter { $0.value > cutoff }
        let liveKeys = Set(checkedAt.keys).union(items.map(\.pr.key))
        threadIds = threadIds.filter { liveKeys.contains($0.key) }
    }
}

public enum FeedStore {
    public static var url: URL { Paths.stateURL }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func load() -> FeedState {
        Migration.migrateIfNeeded()
        guard let data = try? Data(contentsOf: url), let state = try? decoder.decode(FeedState.self, from: data) else {
            return FeedState()
        }
        return state
    }

    public static func save(_ state: FeedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
