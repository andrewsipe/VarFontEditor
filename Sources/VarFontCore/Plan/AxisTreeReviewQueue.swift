import Foundation

public enum AxisTreeReviewItem: Equatable, Sendable {
    case planIssue(PlanWarning)
    case axisConflict(AxisConflictBundle)

    public var axisTag: String? {
        switch self {
        case let .planIssue(warning):
            return warning.axis
        case let .axisConflict(bundle):
            return bundle.axisTag
        }
    }
}

public enum AxisTreeReviewQueue {
    private static func planIssuePriority(_ code: String) -> Int {
        switch code {
        case "orphan_stat_link", "ital_value_name_mismatch", "ital_format1_upgrade", "wght_format1_upgrade":
            return 5
        case "fvar_missing_from_stat", "stat_missing_from_fvar", "default_instance_excluded", "default_instance_not_in_grid":
            return 6
        case "ital_slnt_coexistence":
            return 7
        case "opsz_format2_suggest":
            return 14
        case "registration_mismatch", "registration_value_missing":
            return 8
        case "empty_instance_axis":
            return 9
        case "multiple_elidable":
            return 12
        case "axis_neutral_mismatch", "default_token_names":
            return 30
        case "duplicate_composed_name":
            return 40
        default:
            return 25
        }
    }

    public static func build(
        warnings: [PlanWarning],
        conflictBundles: [AxisConflictBundle],
        namingOrder: [String]
    ) -> [AxisTreeReviewItem] {
        var items: [AxisTreeReviewItem] = []

        for warning in warnings where shouldEnqueuePlanIssue(warning) {
            items.append(.planIssue(warning))
        }

        for bundle in conflictBundles {
            items.append(.axisConflict(bundle))
        }

        return items.sorted { lhs, rhs in
            let lp = priority(for: lhs)
            let rp = priority(for: rhs)
            if lp != rp { return lp < rp }
            return compareTieBreak(lhs, rhs, namingOrder: namingOrder)
        }
    }

    public static func filter(_ items: [AxisTreeReviewItem], axisTag: String) -> [AxisTreeReviewItem] {
        items.filter { $0.axisTag == axisTag }
    }

    public static func informationalWarnings(
        warnings: [PlanWarning],
        namingOrder: [String]
    ) -> [PlanWarning] {
        let suppressed = conflictWarningCodes
        return warnings
            .filter { !suppressed.contains($0.code) }
            .sorted { lhs, rhs in
                let lp = planIssuePriority(lhs.code)
                let rp = planIssuePriority(rhs.code)
                if lp != rp { return lp < rp }
                return (lhs.axis ?? lhs.message) < (rhs.axis ?? rhs.message)
            }
    }

    // MARK: - Private

    private static func shouldEnqueuePlanIssue(_ warning: PlanWarning) -> Bool {
        guard PlanIssueCodes.resolvable.contains(warning.code) else { return false }
        guard !conflictWarningCodes.contains(warning.code) else { return false }
        return true
    }

    private static func priority(for item: AxisTreeReviewItem) -> Int {
        switch item {
        case let .planIssue(warning):
            return planIssuePriority(warning.code)
        case let .axisConflict(bundle):
            return conflictBundlePriority(bundle.kind)
        }
    }

    /// Warnings represented by axis conflict bundles — not duplicated as plan issues.
    private static let conflictWarningCodes: Set<String> = [
        "duplicate_stop_value",
        "duplicate_stop_name",
    ]

    private static func conflictBundlePriority(_ kind: AxisConflictKind) -> Int {
        switch kind {
        case .duplicateValue: return 20
        case .duplicateValueAndName: return 21
        case .duplicateName: return 22
        }
    }

    private static func compareTieBreak(
        _ lhs: AxisTreeReviewItem,
        _ rhs: AxisTreeReviewItem,
        namingOrder: [String]
    ) -> Bool {
        let lAxis = lhs.axisTag ?? ""
        let rAxis = rhs.axisTag ?? ""
        let lIndex = namingOrder.firstIndex(of: lAxis) ?? Int.max
        let rIndex = namingOrder.firstIndex(of: rAxis) ?? Int.max
        if lIndex != rIndex { return lIndex < rIndex }
        return sortLabel(lhs) < sortLabel(rhs)
    }

    private static func sortLabel(_ item: AxisTreeReviewItem) -> String {
        switch item {
        case let .planIssue(warning):
            return warning.message
        case let .axisConflict(bundle):
            return bundle.axisTag
        }
    }
}
