import Foundation

// MARK: - Display taxonomy

public enum SaveReviewDisplayCategory: String, CaseIterable, Sendable, Codable {
    case same
    case protected
    case reflow
    case renamed
    case added
    case removed

    public var filterLabel: String {
        switch self {
        case .same: "Same"
        case .protected: "Protected ID"
        case .reflow: "ID Reflowed"
        case .renamed: "renamed"
        case .added: "added"
        case .removed: "removed"
        }
    }

    /// Prototype / legend order.
    public static let filterOrder: [SaveReviewDisplayCategory] = [
        .same, .protected, .reflow, .renamed, .added, .removed,
    ]

    /// Tab badge numerator — rows that need review attention (not unchanged or read-only).
    public var countsTowardTabChanges: Bool {
        switch self {
        case .same, .protected:
            return false
        case .reflow, .renamed, .added, .removed:
            return true
        }
    }
}

public enum SaveReviewTableTab: String, Sendable, Codable, CaseIterable {
    case stat
    case fvar
    case name

    public var label: String {
        switch self {
        case .stat: "STAT"
        case .fvar: "fvar"
        case .name: "Names (ID 256+)"
        }
    }
}

// MARK: - Presentation tree (UI renders this only)

public struct SaveReviewPresentation: Equatable, Sendable {
    public var tabs: [SaveReviewTabPresentation]

    public init(tabs: [SaveReviewTabPresentation]) {
        self.tabs = tabs
    }

    public static let empty = SaveReviewPresentation(tabs: [])
}

public struct SaveReviewTabPresentation: Equatable, Sendable, Identifiable {
    public var id: SaveReviewTableTab
    public var label: String
    public var headline: String
    public var changedCount: Int
    public var totalCount: Int
    public var sections: [SaveReviewSectionPresentation]

    public var tabID: String { id.rawValue }

    public init(
        id: SaveReviewTableTab,
        label: String,
        headline: String,
        changedCount: Int,
        totalCount: Int,
        sections: [SaveReviewSectionPresentation]
    ) {
        self.id = id
        self.label = label
        self.headline = headline
        self.changedCount = changedCount
        self.totalCount = totalCount
        self.sections = sections
    }
}

public struct SaveReviewSectionPresentation: Equatable, Sendable, Identifiable {
    public var title: String
    public var rows: [SaveReviewRowPresentation]

    public var id: String { title }

    public init(title: String, rows: [SaveReviewRowPresentation]) {
        self.title = title
        self.rows = rows
    }
}

public struct SaveReviewRowPresentation: Equatable, Sendable, Identifiable {
    public var id: String
    /// Name table slot when the row maps to one (shown in the leading column).
    public var nameID: Int?
    public var fieldTitle: String
    public var fieldSubtitle: String
    public var afterValue: String?
    public var wasLine: String?
    public var noteLine: String?
    public var roleLabel: String?
    public var category: SaveReviewDisplayCategory
    public var searchText: String

    public init(
        id: String,
        nameID: Int? = nil,
        fieldTitle: String,
        fieldSubtitle: String,
        afterValue: String?,
        wasLine: String?,
        noteLine: String?,
        roleLabel: String?,
        category: SaveReviewDisplayCategory,
        searchText: String
    ) {
        self.id = id
        self.nameID = nameID
        self.fieldTitle = fieldTitle
        self.fieldSubtitle = fieldSubtitle
        self.afterValue = afterValue
        self.wasLine = wasLine
        self.noteLine = noteLine
        self.roleLabel = roleLabel
        self.category = category
        self.searchText = searchText
    }
}

// MARK: - Category mapping

public enum SaveReviewDisplayCategoryMapper {
    public static func statRowIsReflow(_ row: CommitDiffStatRow) -> Bool {
        row.change == .changed
            && row.beforeName == row.afterName
            && row.beforeNameID != row.afterNameID
    }

    public static func category(for statRow: CommitDiffStatRow) -> SaveReviewDisplayCategory {
        if statRowIsReflow(statRow) { return .reflow }
        switch statRow.change {
        case .added: return .added
        case .removed: return .removed
        case .changed: return .renamed
        case .unchanged: return .same
        }
    }

    public static func category(for instanceRow: CommitDiffInstanceRow) -> SaveReviewDisplayCategory {
        switch instanceRow.change {
        case .added: return .added
        case .removed: return .removed
        case .changed: return .renamed
        case .unchanged: return .same
        }
    }

    public static func postscriptCategory(for instanceRow: CommitDiffInstanceRow) -> SaveReviewDisplayCategory {
        switch instanceRow.postscriptChange {
        case .added: return .added
        case .removed: return .removed
        case .changed: return .renamed
        case .unchanged: return .same
        }
    }

    public static func category(for nameRow: CommitDiffNameIDRow) -> SaveReviewDisplayCategory {
        if nameRow.reflowSuppressed { return .same }
        if nameRow.afterRole == "protected_ot_label" { return .protected }
        if nameRow.reflowedFromNameID != nil { return .reflow }
        switch nameRow.change {
        case .added: return .added
        case .removed: return .removed
        case .changed: return .renamed
        case .unchanged: return .same
        }
    }
}
