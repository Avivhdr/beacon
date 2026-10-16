import Foundation
import Testing
@testable import Core

private let me = Author(login: "Avivhdr")
private let mona = Author(login: "mona")
private let ci = Author(login: "github-actions", isBot: true)
private let ref = PRRef(owner: "octo-org", name: "frontend", number: 1)
private let ctx = ClassifierContext(me: "avivhdr", teams: ["octo-org/docs"], ignoredUsers: ["ci-bot"])

private func t(_ minutes: Double) -> Date { Date(timeIntervalSince1970: 1_000_000 + minutes * 60) }
private func comment(_ id: String, _ author: Author, _ body: String, at minutes: Double) -> PRComment {
    PRComment(id: id, author: author, body: body, createdAt: t(minutes), url: "u/\(id)")
}
private func review(_ id: String, _ author: Author, _ state: String, _ body: String = "", at minutes: Double) -> PRReview {
    PRReview(id: id, author: author, state: state, body: body, submittedAt: t(minutes), url: "u/\(id)")
}
private func pr(author: Author, comments: [PRComment] = [], reviews: [PRReview] = [], threads: [[PRComment]] = []) -> PRDetail {
    PRDetail(ref: ref, title: "Title", url: "u", state: "OPEN", author: author, comments: comments, reviews: reviews, threads: threads)
}
private func kinds(_ detail: PRDetail, since: Double = 0) -> [String: FeedKind] {
    Dictionary(uniqueKeysWithValues: Classifier.classify(detail, since: t(since), context: ctx).map { ($0.id, $0.kind) })
}

@Test func commentsAndReviewsOnMyPR() {
    let result = kinds(pr(author: me,
        comments: [comment("c1", mona, "looks off", at: 1)],
        reviews: [
            review("r1", mona, "APPROVED", at: 2),
            review("r2", mona, "APPROVED", "Good to merge. One optional nit inline.", at: 3),
            review("r3", mona, "CHANGES_REQUESTED", at: 4),
            review("r4", mona, "COMMENTED", at: 5),
            review("r5", mona, "COMMENTED", "a few thoughts", at: 6),
            review("r6", mona, "DISMISSED", "Good to merge", at: 6.5),
            review("r7", mona, "DISMISSED", at: 6.6),
        ],
        threads: [[comment("t1", mona, "inline nit", at: 7)]]
    ))
    #expect(result == [
        "c1": .comment, "r2": .approvedWithComment, "r3": .changesRequested, "r5": .reviewed, "r6": .reviewed, "t1": .comment,
    ])
}

@Test func replyToMyInlineComment() {
    let result = kinds(pr(author: mona, threads: [
        [comment("a", me, "why?", at: 1), comment("b", mona, "because", at: 2)],
        [comment("c", mona, "unrelated thread", at: 3)],
    ]))
    // "c" counts because I commented on the PR before it, just not as a reply.
    #expect(result == ["b": .reply, "c": .comment])
}

@Test func othersPRBeforeIParticipatedIsIgnored() {
    let result = kinds(pr(author: mona, comments: [
        comment("before", mona, "hi", at: 1),
        comment("mine", me, "question", at: 2),
        comment("after", mona, "answer", at: 3),
    ]))
    #expect(result == ["after": .comment])
}

@Test func mentions() {
    let result = kinds(pr(author: mona, comments: [
        comment("direct", mona, "cc @avivhdr", at: 1),
        comment("team", mona, "@octo-org/docs please look", at: 2),
        comment("otherTeam", mona, "@octo-org/robots fyi", at: 3),
        comment("prefix", mona, "@avivhdr-bot ping", at: 4),
        comment("email", mona, "mail x@avivhdr.com", at: 5),
        comment("quoted", mona, "> @avivhdr said this\nI disagree", at: 6),
        comment("quotedCRLF", mona, "> @avivhdr said this\r\n\r\nI disagree", at: 7),
    ]))
    #expect(result == ["direct": .mention, "team": .teamMention])
}

@Test func ignoresMeBotsSkippedUsersAndOldActivity() {
    let result = kinds(pr(author: me, comments: [
        comment("old", mona, "old", at: 1),
        comment("self", me, "note to self", at: 11),
        comment("bot", ci, "coverage report", at: 12),
        comment("cicd", Author(login: "ci-bot"), "Code Review Summary", at: 13),
        comment("new", mona, "new", at: 14),
    ]), since: 10)
    #expect(result == ["new": .comment])
}

@Test func snippetDropsQuotesAndHTMLComments() {
    #expect(Classifier.snippetText("> quoted\n<!-- template -->\nThe   actual\nreply") == "The actual reply")
    #expect(Classifier.snippetText("see <img width=\"10\" src=\"x\"> and ![shot](https://x/y.png) <details><summary>more</summary></details>") == "see [image] and [image] more")
    #expect(Classifier.snippetText("> @mona Should there be a difference?\r\n\r\nThere should be none.") == "There should be none.")
    #expect(Classifier.snippetText("> Good to merge.\r\n> \r\n> One nit") == "Good to merge. One nit")
}

@Test func mergeKeepsReadStateAndUpdatesPRState() {
    var state = FeedState()
    let first = Classifier.classify(pr(author: me, comments: [comment("c1", mona, "x", at: 1)]), since: t(0), context: ctx)
    #expect(state.merge(first, for: pr(author: me)).count == 1)
    state.items[0].read = true

    var merged = pr(author: me, comments: [comment("c1", mona, "x", at: 1), comment("c2", mona, "y", at: 2)])
    merged.state = "MERGED"
    let added = state.merge(Classifier.classify(merged, since: t(0), context: ctx), for: merged)
    #expect(added.map(\.id) == ["c2"])
    #expect(state.items.first { $0.id == "c1" }?.read == true)
    #expect(state.items.allSatisfy { $0.prState == "MERGED" })
}

@Test func parsesPRRefFromAPIURL() {
    #expect(PRRef(apiURL: "https://api.github.com/repos/octo-org/frontend/pulls/128") == PRRef(owner: "octo-org", name: "frontend", number: 128))
    #expect(PRRef(apiURL: "https://api.github.com/repos/octo-org/frontend/issues/1") == nil)
}

@Test func bareApprovalIsNotTakingPart() {
    // A bare approval is not taking part, so a later question to the author stays out.
    let result = kinds(pr(author: mona,
        comments: [comment("q", Author(login: "hubot"), "Hey @mona , any impact on test speed?", at: 2)],
        reviews: [review("approve", me, "APPROVED", at: 1)]
    ))
    #expect(result.isEmpty)
}

@Test func commentAddressedToSomeoneElse() {
    let hubot = Author(login: "hubot")
    let othersPR = kinds(pr(author: mona, comments: [
        comment("mine", me, "question", at: 1),
        comment("toMona", hubot, "@mona any impact?", at: 2),
        comment("toAll", hubot, "any impact?", at: 3),
    ]))
    #expect(othersPR == ["toAll": .comment])

    let myPR = kinds(pr(author: me, comments: [comment("toMona", hubot, "@mona can you check this?", at: 2)]))
    #expect(myPR == ["toMona": .comment])

    let replyInMyThread = kinds(pr(author: mona, threads: [
        [comment("a", me, "why?", at: 1), comment("b", mona, "@hubot knows", at: 2)],
    ]))
    #expect(replyInMyThread == ["b": .reply])
}

@Test func categoryQueryAddsRepoFilters() {
    var category = Category(name: "Mine", query: "is:pr review-requested:@me {teammates}", includeRepos: ["octo-org/frontend"], excludeRepos: ["octo-org/b"])
    #expect(category.searchQuery(teammates: []) == nil)
    #expect(category.searchQuery(teammates: ["mona", "hubot"], alsoExcluding: ["octo-org/a", "octo-org/frontend"])
        == "is:pr review-requested:@me author:mona author:hubot repo:octo-org/frontend -repo:octo-org/a -repo:octo-org/b")
    category.query = "is:pr"
    category.includeRepos = []
    #expect(category.searchQuery(teammates: []) == "is:pr -repo:octo-org/b")
}

@Test func configRoundTripsWithoutIds() throws {
    var config = Config()
    config.excludeRepos = ["octo-org/x"]
    let data = try JSONEncoder().encode(config)
    #expect(!String(decoding: data, as: UTF8.self).contains("\"id\""))
    let decoded = try JSONDecoder().decode(Config.self, from: data)
    #expect(decoded.excludeRepos == ["octo-org/x"])
    #expect(decoded.categories.map(\.name) == config.categories.map(\.name))
}

@Test func skipLabelsSinkToTheBottom() {
    func pr(_ id: String, _ labels: [String]) -> ReviewPR {
        ReviewPR(id: id, repo: "octo-org/frontend", number: 1, title: id, url: "u", author: "mona", createdAt: Date(), ciState: nil,
                 labels: labels.map { PRLabel(name: $0, color: "D93F0B") })
    }
    let sorted = FeedEngine.markSkipped(
        [pr("a", ["DO NOT REVIEW"]), pr("b", []), pr("c", ["Do not review", "bug"]), pr("d", ["DO NOT MERGE"])],
        labels: ["DO NOT REVIEW"]
    )
    #expect(sorted.map(\.id) == ["b", "d", "a", "c"])
    #expect(sorted.filter(\.isSkipped).map { $0.skipLabels.map(\.name) } == [["DO NOT REVIEW"], ["Do not review"]])
}
