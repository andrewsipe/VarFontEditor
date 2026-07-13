import Foundation

public enum AxisStopNamingDefaults {
    private static let defaultTokenNames: Set<String> = [
        "regular", "normal", "roman", "upright", "standard", "italic", "oblique",
    ]

    public static func defaultElidableName(for tag: String) -> String? {
        switch tag {
        case "wght": return "Regular"
        case "wdth": return "Normal"
        case "ital": return "Roman"
        case "slnt": return "Upright"
        case "opsz": return "Regular"
        default: return nil
        }
    }

    public static func suggestedName(for stop: AxisValue, axisTag: String) -> String {
        if stop.elidable, let elidable = defaultElidableName(for: axisTag) {
            return elidable
        }
        if axisTag == "ital" || axisTag == "slnt" {
            let lowered = stop.name.lowercased()
            if lowered.contains("italic") { return "Italic" }
            if lowered.contains("oblique") { return "Oblique" }
        }
        return AxisCoordinateFormat.format(stop.value)
    }

    public static func renameFromValueAction(stopID: String, stop: AxisValue) -> ConflictFixAction {
        .renameStop(stopID: stopID, newName: AxisCoordinateFormat.format(stop.value))
    }

    public static func bulkRenameFromValues(stops: [AxisValue]) -> ConflictFixAction {
        .compound(stops.map { renameFromValueAction(stopID: $0.id, stop: $0) })
    }

    public static func bulkApplyDefaults(axis: AxisDefinition, stopIDs: [String]) -> ConflictFixAction {
        let idSet = Set(stopIDs)
        let involved = axis.values.filter { idSet.contains($0.id) }
        guard !involved.isEmpty else { return .compound([]) }

        let elidableDefault = defaultElidableName(for: axis.tag)
        let elidableStop = involved.first(where: \.elidable)
            ?? involved.min(by: { $0.value < $1.value })
        var actions: [ConflictFixAction] = []

        if let elidableStop {
            for stop in involved where stop.id != elidableStop.id && stop.elidable {
                actions.append(.setElidable(stopID: stop.id, elidable: false))
            }
            actions.append(.setElidable(stopID: elidableStop.id, elidable: true))
        }

        for stop in involved {
            let name: String
            if stop.id == elidableStop?.id, let elidableDefault {
                name = elidableDefault
            } else {
                name = suggestedName(for: stop, axisTag: axis.tag)
            }
            if stop.name != name {
                actions.append(.renameStop(stopID: stop.id, newName: name))
            }
        }

        return .compound(actions)
    }

    private static let crossAxisNeutralTokens: Set<String> = [
        "regular", "normal", "roman", "upright", "standard",
    ]

    public static func isCrossAxisNeutralToken(_ name: String) -> Bool {
        crossAxisNeutralTokens.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public static func hasAxisNeutralMismatch(_ font: FontDocument) -> Bool {
        font.axes.contains { axis in
            guard axis.role == .instance, let neutral = defaultElidableName(for: axis.tag) else {
                return false
            }
            return axis.values.contains { stop in
                isCrossAxisNeutralToken(stop.name)
                    && stop.name.caseInsensitiveCompare(neutral) != .orderedSame
            }
        }
    }

    public static func applyAxisNeutralsToAllInstanceAxes(font: inout FontDocument) {
        for axisIndex in font.axes.indices {
            let axis = font.axes[axisIndex]
            guard axis.role == .instance,
                  let neutral = defaultElidableName(for: axis.tag) else { continue }

            for stopIndex in font.axes[axisIndex].values.indices {
                let stop = font.axes[axisIndex].values[stopIndex]
                guard isCrossAxisNeutralToken(stop.name) else { continue }
                guard stop.name.caseInsensitiveCompare(neutral) != .orderedSame else { continue }
                font.axes[axisIndex].values[stopIndex].name = neutral
            }
        }
    }

    /// True when any instance axis has every stop sharing one name.
    public static func hasUniformStopNamesOnInstanceAxes(_ font: FontDocument) -> Bool {
        font.axes.contains { hasUniformStopNames(on: $0) }
    }

    public static func hasUniformStopNames(on axis: AxisDefinition) -> Bool {
        guard axis.role == .instance, axis.values.count >= 2 else { return false }
        return Set(axis.values.map(\.name)).count == 1
    }

    public static func hasInstanceAxisValueConflicts(_ font: FontDocument) -> Bool {
        !axesWithValueConflicts(in: font).isEmpty
    }

    public static func axesWithValueConflicts(in font: FontDocument) -> [String] {
        var tags: [String] = []
        for axis in font.axes where axis.role == .instance {
            var seen: [Double] = []
            var hasDuplicate = false
            for stop in axis.values {
                if seen.contains(where: { AxisCoordinate.valuesEqual($0, stop.value) }) {
                    hasDuplicate = true
                    break
                }
                seen.append(stop.value)
            }
            if hasDuplicate {
                tags.append(axis.tag)
            }
        }
        return tags.sorted()
    }

    public struct AxisNeutralMismatch: Equatable, Sendable {
        public var axisLabel: String
        public var fromName: String
        public var toName: String
    }

    public static func axisNeutralMismatches(in font: FontDocument) -> [AxisNeutralMismatch] {
        var mismatches: [AxisNeutralMismatch] = []
        for axis in font.axes where axis.role == .instance {
            guard let expected = defaultElidableName(for: axis.tag) else { continue }
            for stop in axis.values where isCrossAxisNeutralToken(stop.name)
                && stop.name.caseInsensitiveCompare(expected) != .orderedSame {
                mismatches.append(
                    AxisNeutralMismatch(
                        axisLabel: axisLabel(axis),
                        fromName: stop.name,
                        toName: expected
                    )
                )
            }
        }
        return mismatches
    }

    public static func axisNeutralMismatchDescriptions(in font: FontDocument) -> [String] {
        axisNeutralMismatches(in: font).map(translationPhrase)
    }

    public static func axisNeutralMismatchWarningMessage(for font: FontDocument) -> String {
        let mismatches = axisNeutralMismatches(in: font)
        guard !mismatches.isEmpty else { return "" }
        return "For composed names, this tool translates \(joinedTranslations(mismatches))."
    }

    public static func applyAxisNeutralsDetail(for font: FontDocument) -> String {
        let mismatches = axisNeutralMismatches(in: font)
        guard !mismatches.isEmpty else {
            return "Set each axis default stop to its neutral label (e.g. Normal, Regular, Roman) so composed names do not repeat."
        }
        let stopWord = mismatches.count == 1 ? "stop" : "stops"
        return "Align baseline labels on \(mismatches.count) \(stopWord). For composed names, this tool translates \(joinedTranslations(mismatches))."
    }

    private static func translationPhrase(_ mismatch: AxisNeutralMismatch) -> String {
        "\(mismatch.axisLabel) “\(mismatch.fromName)” to “\(mismatch.toName)”"
    }

    private static func joinedTranslations(_ mismatches: [AxisNeutralMismatch]) -> String {
        let phrases = mismatches.map(translationPhrase)
        switch phrases.count {
        case 0:
            return ""
        case 1:
            return phrases[0]
        case 2:
            return "\(phrases[0]), and \(phrases[1])"
        default:
            let head = phrases.dropLast().joined(separator: ", ")
            return "\(head), and \(phrases.last!)"
        }
    }

    public static func wouldChangeFromApplyAxisNeutrals(_ font: FontDocument) -> Bool {
        hasAxisNeutralMismatch(font)
    }

    public static func wouldChangeFromApplyAxisDefaults(_ font: FontDocument) -> Bool {
        font.axes.contains { axis in
            guard axis.role == .instance, shouldApplyAxisDefaults(to: axis) else { return false }
            return axis.values.contains { stop in
                stop.name != suggestedName(for: stop, axisTag: axis.tag)
            }
        }
    }

    private static func shouldApplyAxisDefaults(to axis: AxisDefinition) -> Bool {
        guard axis.role == .instance, axis.values.count >= 2 else { return false }
        if hasUniformStopNames(on: axis) { return true }
        return axis.values.allSatisfy { isCrossAxisNeutralToken($0.name) }
    }

    private static func axisLabel(_ axis: AxisDefinition) -> String {
        if let displayName = axis.displayName, !displayName.isEmpty {
            return "\(displayName) (\(axis.tag))"
        }
        return axis.tag
    }

    public static func axesAffectedByApplyDefaults(_ font: FontDocument) -> [AxisDefinition] {
        font.axes.filter { axis in
            guard axis.role == .instance, shouldApplyAxisDefaults(to: axis) else { return false }
            return axis.values.contains { stop in
                stop.name != suggestedName(for: stop, axisTag: axis.tag)
            }
        }
    }

    public static func axisLabelsForApplyDefaults(_ font: FontDocument) -> [String] {
        axesAffectedByApplyDefaults(font).map { axis in
            if let name = axis.displayName, !name.isEmpty {
                return "\(name) (\(axis.values.count) stops)"
            }
            return "\(axis.tag) (\(axis.values.count) stops)"
        }
    }

    public static func applyAxisDefaultsDetail(for font: FontDocument) -> String {
        let labels = axisLabelsForApplyDefaults(font)
        guard !labels.isEmpty else {
            return "This tool renames non-default stops to their coordinate values, so composed names come out distinct."
        }
        if labels.count == 1 {
            return "For composed names, this tool renames stops on \(labels[0]) to their coordinate values — the elidable stop keeps its axis neutral."
        }
        return "For composed names, this tool renames stops on \(labels.joined(separator: ", ")) to their coordinate values. Elidable stops keep their axis neutrals."
    }

    public static func applyAxisDefaultsToAllInstanceAxes(font: inout FontDocument) {
        for axis in font.axes where axis.role == .instance && shouldApplyAxisDefaults(to: axis) {
            let action = bulkApplyDefaults(axis: axis, stopIDs: axis.values.map(\.id))
            ConflictResolver.apply(action, axisTag: axis.tag, to: &font)
        }
    }

    public static func isDefaultTokenName(_ name: String) -> Bool {
        defaultTokenNames.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public static func composedNameUsesOnlyDefaultTokens(_ name: String, elidedFallback: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare(elidedFallback) == .orderedSame { return true }
        let parts = trimmed.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { isDefaultTokenName($0) }
    }
}
