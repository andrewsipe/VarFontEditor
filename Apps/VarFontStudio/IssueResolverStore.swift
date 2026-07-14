import Combine
import Foundation
import VarFontCore

struct AxisConflictResolverSession: Identifiable {
    let id = UUID()
    let bundle: AxisConflictBundle
    let reviewPosition: Int?
    let reviewTotal: Int?
}

struct PlanIssueResolverSession: Identifiable {
    let id = UUID()
    let warning: PlanWarning
    let reviewPosition: Int?
    let reviewTotal: Int?
}

struct AxisTreeReviewSession {
    var state: AxisTreeReviewSessionState
}

/// Conflict / plan-issue session state **and** orchestration (via `IssueResolverHost`).
@MainActor
final class IssueResolverStore: ObservableObject {
    /// Set by `EditorViewModel` in `init`.
    weak var host: (any IssueResolverHost)?

    var requireHost: any IssueResolverHost {
        guard let host else {
            preconditionFailure("IssueResolverStore.host was not set")
        }
        return host
    }

    @Published var conflictResolverRequest: AxisConflictResolverSession?
    @Published var planIssueResolverRequest: PlanIssueResolverSession?

    private(set) var reviewSession: AxisTreeReviewSession?

    var hasActiveReviewSession: Bool { reviewSession != nil }

    func startReviewSession(state: AxisTreeReviewSessionState) {
        reviewSession = AxisTreeReviewSession(state: state)
    }

    func updateReviewSession(_ transform: (inout AxisTreeReviewSession) -> Void) {
        guard var session = reviewSession else { return }
        transform(&session)
        reviewSession = session
    }

    func endReviewSession() {
        reviewSession = nil
    }

    func reviewSessionPosition() -> (current: Int, total: Int)? {
        reviewSession?.state.displayPosition()
    }

    func presentConflict(
        bundle: AxisConflictBundle,
        reviewPosition: Int?,
        reviewTotal: Int?
    ) {
        conflictResolverRequest = AxisConflictResolverSession(
            bundle: bundle,
            reviewPosition: reviewPosition,
            reviewTotal: reviewTotal
        )
    }

    func presentPlanIssue(
        warning: PlanWarning,
        reviewPosition: Int?,
        reviewTotal: Int?
    ) {
        planIssueResolverRequest = PlanIssueResolverSession(
            warning: warning,
            reviewPosition: reviewPosition,
            reviewTotal: reviewTotal
        )
    }

    func dismissConflictResolver(clearReviewSession: Bool) {
        conflictResolverRequest = nil
        if clearReviewSession {
            reviewSession = nil
        }
    }

    func dismissPlanIssueResolver(clearReviewSession: Bool) {
        planIssueResolverRequest = nil
        if clearReviewSession {
            reviewSession = nil
        }
    }

    func clearBothResolvers() {
        planIssueResolverRequest = nil
        conflictResolverRequest = nil
    }

    func clearBothResolversAndReviewSession() {
        clearBothResolvers()
        reviewSession = nil
    }
}
