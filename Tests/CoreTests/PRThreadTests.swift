import Foundation
import Testing
@testable import Core

private func item(_ id: String, pr number: Int, at minutes: Double, title: String = "t", read: Bool = false) -> FeedItem {
    FeedItem(
        id: id,
        kind: .comment,
        actor: "mona",
        pr: PRRef(owner: "octo-org", name: "frontend", number: number),
        prTitle: title,
        prState: "OPEN",
        onMyPR: true,
        snippet: "",
        url: "u/\(id)",
        createdAt: Date(timeIntervalSince1970: 1_000_000 + minutes * 60),
        read: read
    )
}

@Test func itemsOnTheSamePullRequestShareAThread() {
    let threads = PRThread.group([item("a", pr: 1, at: 10), item("b", pr: 2, at: 20), item("c", pr: 1, at: 30)])
    #expect(threads.map(\.pr.number) == [1, 2])
    #expect(threads.map { $0.items.map(\.id) } == [["c", "a"], ["b"]])
}

@Test func threadTakesTitleFromItsNewestItem() {
    let threads = PRThread.group([item("a", pr: 1, at: 10, title: "Old"), item("b", pr: 1, at: 20, title: "Renamed")])
    #expect(threads.first?.title == "Renamed")
}

@Test func threadCountsOnlyUnreadItems() {
    let threads = PRThread.group([item("a", pr: 1, at: 10, read: true), item("b", pr: 1, at: 20), item("c", pr: 1, at: 30)])
    #expect(threads.first?.unreadCount == 2)
}

@Test func threadsWithTheSameLatestTimeKeepAStableOrder() {
    let threads = PRThread.group([item("a", pr: 9, at: 10), item("b", pr: 3, at: 10)])
    #expect(threads.map(\.id) == ["octo-org/frontend#3", "octo-org/frontend#9"])
}
