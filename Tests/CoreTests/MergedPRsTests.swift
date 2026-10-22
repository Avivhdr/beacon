import Foundation
import Testing
@testable import Core

private func merged(_ repo: String, _ number: Int, at offset: TimeInterval?) -> ReviewPR {
    ReviewPR(
        id: "\(repo)#\(number)",
        repo: repo,
        number: number,
        title: "t",
        url: "u",
        author: "mona",
        createdAt: Date(timeIntervalSince1970: 0),
        ciState: nil,
        mergedAt: offset.map { Date(timeIntervalSince1970: $0) }
    )
}

@Test func newestMergeComesFirst() {
    let prs = MergedPRs.byDate([
        merged("octo-org/docs", 1, at: 10),
        merged("octo-org/frontend", 2, at: 30),
        merged("octo-org/frontend", 3, at: 20),
    ])
    #expect(prs.map(\.id) == ["octo-org/frontend#2", "octo-org/frontend#3", "octo-org/docs#1"])
}

@Test func missingMergeDateSortsLast() {
    let prs = MergedPRs.byDate([
        merged("octo-org/docs", 1, at: nil),
        merged("octo-org/frontend", 2, at: 5),
    ])
    #expect(prs.map(\.id) == ["octo-org/frontend#2", "octo-org/docs#1"])
}

@Test func sameMergeDateKeepsIdOrder() {
    let prs = MergedPRs.byDate([
        merged("octo-org/frontend", 9, at: 10),
        merged("octo-org/docs", 2, at: 10),
    ])
    #expect(prs.map(\.id) == ["octo-org/docs#2", "octo-org/frontend#9"])
}

@Test func repositoriesFollowTheirNewestMerge() {
    let groups = MergedPRs.byRepo([
        merged("octo-org/docs", 4, at: 15),
        merged("octo-org/frontend", 8, at: 10),
        merged("octo-org/frontend", 9, at: 40),
        merged("octocat/hello-world", 1, at: 20),
    ])
    #expect(groups.map(\.repo) == ["octo-org/frontend", "octocat/hello-world", "octo-org/docs"])
    #expect(groups[0].prs.map(\.number) == [9, 8])
    #expect(groups[1].prs.map(\.number) == [1])
    #expect(groups[2].prs.map(\.number) == [4])
}
