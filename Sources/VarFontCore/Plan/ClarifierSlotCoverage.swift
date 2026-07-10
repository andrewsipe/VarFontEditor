import Foundation

public enum ClarifierSlotState: Equatable, Sendable {
    case editable
    case coveredByRegistration(axisTag: String)
    case coveredByInstanceAxis(axisTag: String)
    case readOnlyMaster
}

public enum ClarifierSlotCoverage {
    /// Resolve UI/infer state for a clarifier slot.
    /// Precedence: registration coverage → instance-axis coverage → multi-file master → editable.
    public static func slotState(
        category: FileClarifierCategory,
        font: FontDocument,
        projectFontCount: Int = 1
    ) -> ClarifierSlotState {
        if category == .custom {
            if isReadOnlyMaster(font: font, projectFontCount: projectFontCount) {
                return .readOnlyMaster
            }
            return .editable
        }

        if let tag = registrationAxisTagCovering(category: category, font: font) {
            return .coveredByRegistration(axisTag: tag)
        }
        if let tag = instanceAxisTagCovering(category: category, font: font) {
            return .coveredByInstanceAxis(axisTag: tag)
        }
        if isReadOnlyMaster(font: font, projectFontCount: projectFontCount) {
            return .readOnlyMaster
        }
        return .editable
    }

    public static func skippedCategories(font: FontDocument) -> Set<FileClarifierCategory> {
        var skipped = Set<FileClarifierCategory>()
        for category in [FileClarifierCategory.slope, .width, .optical] {
            switch slotState(category: category, font: font) {
            case .coveredByRegistration, .coveredByInstanceAxis:
                skipped.insert(category)
            case .editable, .readOnlyMaster:
                break
            }
        }
        return skipped
    }

    public static func hasEditableInferSlots(font: FontDocument, projectFontCount: Int) -> Bool {
        for category in [FileClarifierCategory.slope, .width, .optical] {
            if slotState(category: category, font: font, projectFontCount: projectFontCount) == .editable {
                return true
            }
        }
        if slotState(category: .custom, font: font, projectFontCount: projectFontCount) == .editable {
            let hasCustom = font.fileRole?.label(for: .custom)?
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            if !hasCustom { return true }
        }
        return false
    }

    private static func isReadOnlyMaster(font: FontDocument, projectFontCount: Int) -> Bool {
        font.fileRole?.kind == .master && projectFontCount > 1
    }

    private static func registrationAxisTagCovering(
        category: FileClarifierCategory,
        font: FontDocument
    ) -> String? {
        for tag in font.fileStatRegistration.keys {
            guard let axis = font.axes.first(where: { $0.tag == tag }),
                  axis.isDesignRecordOnly else { continue }
            guard categoryForRegistrationAxis(tag) == category else { continue }
            return tag
        }
        return nil
    }

    private static func instanceAxisTagCovering(
        category: FileClarifierCategory,
        font: FontDocument
    ) -> String? {
        switch category {
        case .slope:
            if font.axes.contains(where: { $0.tag == "ital" }) {
                return "ital"
            }
            if font.axes.contains(where: { $0.tag == "slnt" && $0.role == .instance }) {
                return "slnt"
            }
        case .width:
            if font.axes.contains(where: { $0.tag == "wdth" && $0.role == .instance }) {
                return "wdth"
            }
        case .optical:
            if font.axes.contains(where: { $0.tag == "opsz" && $0.role == .instance }) {
                return "opsz"
            }
        case .custom:
            break
        }
        return nil
    }

    private static func categoryForRegistrationAxis(_ tag: String) -> FileClarifierCategory? {
        switch tag {
        case "ital", "slnt": return .slope
        case "wdth": return .width
        case "opsz": return .optical
        default: return nil
        }
    }
}
