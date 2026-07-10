import Foundation
import VarFontCore

/// Dry-run result and diff report shown before writing a patched font copy.
struct CommitPreflightSession: Identifiable {
    let id = UUID()
    let projectID: String
    let fontID: String
    let dryRunRequest: CommitRequest
    let baseRequest: CommitRequest
    let preflight: CommitResult
    let diffReport: CommitDiffReport
    /// UI-ready tabbed presentation (built at preflight time).
    let presentation: SaveReviewPresentation
    /// Non-blocking notes (e.g. project fvar scale drift vs source). Kept for export/debug — not rendered in UI.
    let informationalNotes: [String]
}

struct SaveReviewOpenRequest: Equatable {
    let projectID: String
    let token: UUID
}

/// Per-project Save Review chrome state (filters, tab, search).
struct SaveReviewUIState: Equatable {
    var selectedTableTab: SaveReviewTableTab = .stat
    var userPickedTableTab: Bool = false
    var hiddenCategories: Set<SaveReviewDisplayCategory> = []
    var isolateCategory: SaveReviewDisplayCategory? = nil
    var searchQuery: String = ""
}
