import Foundation
import Testing
@testable import Core

private func mine(ci: String? = "SUCCESS", decision: String? = nil, draft: Bool = false, mergeable: String? = nil) -> ReviewPR {
    ReviewPR(
        id: "octo-org/docs#1",
        repo: "octo-org/docs",
        number: 1,
        title: "t",
        url: "u",
        author: "mona",
        createdAt: Date(timeIntervalSince1970: 0),
        ciState: ci,
        isDraft: draft,
        reviewDecision: decision,
        mergeable: mergeable
    )
}

private let ciStates: [String?] = ["SUCCESS", "FAILURE", "ERROR", "PENDING", "EXPECTED", nil]
private let decisions: [String?] = ["APPROVED", "CHANGES_REQUESTED", "REVIEW_REQUIRED", nil]

@Test func everyPullRequestHasExactlyOneStatus() {
    for ci in ciStates {
        for decision in decisions {
            for draft in [false, true] {
                for mergeable in ["MERGEABLE", "CONFLICTING", "UNKNOWN", nil] as [String?] {
                    let pr = mine(ci: ci, decision: decision, draft: draft, mergeable: mergeable)
                    #expect(MineStatus.allCases.filter { $0.matches(pr) }.count == 1)
                }
            }
        }
    }
}

@Test func readyNeedsNothingFromAnyoneElse() {
    #expect(MineStatus(mine(ci: "SUCCESS", decision: "APPROVED")) == .ready)
    #expect(MineStatus(mine(ci: nil, decision: "APPROVED")) == .ready)
    #expect(MineStatus(mine(ci: "SUCCESS", decision: nil)) == .ready)
    #expect(MineStatus(mine(ci: nil, decision: nil)) == .ready)
}

@Test func failingCIComesBeforeEveryReviewDecision() {
    for decision in decisions {
        #expect(MineStatus(mine(ci: "FAILURE", decision: decision)) == .failingCI)
        #expect(MineStatus(mine(ci: "ERROR", decision: decision)) == .failingCI)
    }
}

@Test func changesRequestedWinsOverRunningChecks() {
    #expect(MineStatus(mine(ci: "SUCCESS", decision: "CHANGES_REQUESTED")) == .toFix)
    #expect(MineStatus(mine(ci: "PENDING", decision: "CHANGES_REQUESTED")) == .toFix)
    #expect(MineStatus(mine(ci: nil, decision: "CHANGES_REQUESTED")) == .toFix)
}

@Test func conflictsNeedYouEvenWhenApprovedOrWaiting() {
    #expect(MineStatus(mine(ci: "SUCCESS", decision: "APPROVED", mergeable: "CONFLICTING")) == .toFix)
    #expect(MineStatus(mine(ci: nil, decision: nil, mergeable: "CONFLICTING")) == .toFix)
    #expect(MineStatus(mine(ci: "PENDING", decision: "REVIEW_REQUIRED", mergeable: "CONFLICTING")) == .toFix)
}

@Test func conflictsDoNotOutrankFailingChecksOrDrafts() {
    #expect(MineStatus(mine(ci: "FAILURE", mergeable: "CONFLICTING")) == .failingCI)
    #expect(MineStatus(mine(ci: "SUCCESS", draft: true, mergeable: "CONFLICTING")) == .waiting)
}

@Test func unknownMergeabilityIsNotAConflict() {
    #expect(MineStatus(mine(ci: "SUCCESS", decision: "APPROVED", mergeable: "UNKNOWN")) == .ready)
}

@Test func runningChecksAndPendingReviewsWait() {
    #expect(MineStatus(mine(ci: "PENDING", decision: "APPROVED")) == .waiting)
    #expect(MineStatus(mine(ci: "EXPECTED", decision: nil)) == .waiting)
    #expect(MineStatus(mine(ci: "SUCCESS", decision: "REVIEW_REQUIRED")) == .waiting)
    #expect(MineStatus(mine(ci: nil, decision: "REVIEW_REQUIRED")) == .waiting)
}

@Test func draftsAlwaysWait() {
    for ci in ciStates {
        for decision in decisions {
            #expect(MineStatus(mine(ci: ci, decision: decision, draft: true)) == .waiting)
        }
    }
}
