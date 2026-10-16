import Foundation
import Testing
@testable import Core

private func pr(_ repo: String, _ number: Int) -> ReviewPR {
    ReviewPR(id: "\(repo)#\(number)", repo: repo, number: number, title: "t", url: "u", author: "mona", createdAt: Date(), ciState: nil)
}

private func names(_ results: [CategoryResult]) -> [String: [String]] {
    Dictionary(uniqueKeysWithValues: results.map { ($0.name, $0.prs.map(\.id)) })
}

@Test func bareOrgMatchesEveryRepoItOwns() {
    let work = PRGroup(name: "Work", repos: ["Octo-org"])
    #expect(work.lists("octo-org/frontend"))
    #expect(!work.lists("octo-org-labs/frontend"))
    #expect(!work.lists("octocat/hello-world"))
}

@Test func emptyGroupTakesWhatTheOthersDidNot() {
    let groups = [PRGroup(name: "Work", repos: ["octo-org"]), PRGroup(name: "Private")]
    let result = PRGroup.assign([pr("octo-org/frontend", 1), pr("octocat/hello-world", 2), pr("octo-org/docs", 3)], to: groups)
    #expect(result.map(\.name) == ["Work", "Private"])
    #expect(names(result) == ["Work": ["octo-org/frontend#1", "octo-org/docs#3"], "Private": ["octocat/hello-world#2"]])
    #expect(result.map(\.count) == [2, 1])
}

@Test func firstListingGroupWinsEvenAfterTheCatchAll() {
    let groups = [PRGroup(name: "Other"), PRGroup(name: "Frontend", repos: ["octo-org/frontend"]), PRGroup(name: "Work", repos: ["octo-org"])]
    let result = PRGroup.assign([pr("octo-org/frontend", 1), pr("octo-org/docs", 2), pr("octocat/hello-world", 3)], to: groups)
    #expect(names(result) == ["Other": ["octocat/hello-world#3"], "Frontend": ["octo-org/frontend#1"], "Work": ["octo-org/docs#2"]])
}

@Test func withoutACatchAllUnlistedPRsAreLeftOut() {
    let result = PRGroup.assign([pr("octo-org/frontend", 1), pr("octocat/hello-world", 2)], to: [PRGroup(name: "Work", repos: ["octo-org"])])
    #expect(names(result) == ["Work": ["octo-org/frontend#1"]])
}
