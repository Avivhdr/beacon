import Foundation

/// The Mine header's counts. Each pull request has exactly one status, so the counts sum to the Mine total.
/// Each count also filters the Mine list, so a count and its list always agree.
public enum MineStatus: String, CaseIterable, Identifiable {
    case ready = "Ready"
    case toFix = "To fix"
    case failingCI = "Failing CI"
    case waiting = "Waiting"

    public var id: String { rawValue }

    /// The first rule that fits wins. Failing CI comes before To fix, because a fix to the checks comes first.
    /// To fix means the code must change: a reviewer asked for it, or the branch has merge conflicts.
    public init(_ pr: ReviewPR) {
        if pr.isDraft {
            self = .waiting
        } else if pr.ciFailing {
            self = .failingCI
        } else if pr.reviewDecision == "CHANGES_REQUESTED" || pr.hasConflicts {
            self = .toFix
        } else if pr.ciRunning || pr.reviewDecision == "REVIEW_REQUIRED" {
            self = .waiting
        } else {
            // Approved, or no decision because the repo doesn't require reviews.
            self = .ready
        }
    }

    public func matches(_ pr: ReviewPR) -> Bool {
        MineStatus(pr) == self
    }
}
