import Foundation

/// Groups STAT format 3 linked stops for axis-tree display.
public enum StatFormat3Pairing {
    public enum RowKind: Equatable, Sendable {
        case single(AxisValue)
        case pair(primary: AxisValue, linked: AxisValue?)
    }

    public struct DisplayRow: Identifiable, Equatable, Sendable {
        public var id: String
        public var kind: RowKind

        public init(id: String, kind: RowKind) {
            self.id = id
            self.kind = kind
        }
    }

    public static func displayRows(for stops: [AxisValue]) -> [DisplayRow] {
        var consumed = Set<String>()
        var rows: [DisplayRow] = []

        for stop in stops {
            guard !consumed.contains(stop.id) else { continue }

            if stop.statFormat == 3, stop.linkedValue != nil {
                let linked = resolveLinkedTarget(for: stop, in: stops)
                if let linked {
                    consumed.insert(linked.id)
                }
                consumed.insert(stop.id)
                rows.append(DisplayRow(id: "pair-\(stop.id)", kind: .pair(primary: stop, linked: linked)))
                continue
            }

            if isLinkedTarget(ofAnotherFormat3Stop: stop, in: stops) {
                continue
            }

            consumed.insert(stop.id)
            rows.append(DisplayRow(id: stop.id, kind: .single(stop)))
        }

        return rows
    }

    public static func orphanLinkWarnings(for axis: AxisDefinition) -> [PlanWarning] {
        var warnings: [PlanWarning] = []
        for stop in axis.values where stop.statFormat == 3 {
            guard let linkedValue = stop.linkedValue else { continue }
            if isConventionStyleLink(axis: axis, stop: stop, linkedValue: linkedValue) {
                continue
            }
            if resolveLinkedTarget(for: stop, in: axis.values) == nil {
                warnings.append(
                    PlanWarning(
                        code: "orphan_stat_link",
                        axis: axis.tag,
                        stopIDs: [stop.id],
                        message: "Axis '\(axis.tag)' stop “\(stop.name)” links to missing value \(formatValue(linkedValue)).",
                        hint: "This link points at a coordinate with no stop — add one there, or clear the link."
                    )
                )
            }
        }
        return warnings
    }

    /// Format 3 links that follow registered axis conventions (e.g. ital 0↔1, wght 400↔700) do not
    /// require a named stop at the linked coordinate.
    public static func isConventionStyleLink(
        axis: AxisDefinition,
        stop: AxisValue,
        linkedValue: Double? = nil
    ) -> Bool {
        let linked = linkedValue ?? stop.linkedValue
        guard stop.statFormat == 3, let linked else { return false }
        switch axis.tag {
        case "ital":
            if AxisCoordinate.valuesEqual(stop.value, 0), AxisCoordinate.valuesEqual(linked, 1) {
                return true
            }
            if AxisCoordinate.valuesEqual(stop.value, 1), AxisCoordinate.valuesEqual(linked, 0) {
                return true
            }
        case "wght":
            if AxisCoordinate.valuesEqual(stop.value, 400), AxisCoordinate.valuesEqual(linked, 700) {
                return true
            }
            if AxisCoordinate.valuesEqual(stop.value, 700), AxisCoordinate.valuesEqual(linked, 400) {
                return true
            }
        default:
            break
        }
        return false
    }

    public static func format1UpgradeWarnings(font: FontDocument) -> [PlanWarning] {
        var warnings: [PlanWarning] = []
        for axis in font.axes {
            warnings.append(contentsOf: format1UpgradeWarnings(for: axis))
        }
        return warnings
    }

    public static func format1UpgradeWarnings(for axis: AxisDefinition) -> [PlanWarning] {
        guard axis.tag == "ital" || axis.tag == "wght" else { return [] }
        var warnings: [PlanWarning] = []
        for stop in axis.values where shouldUpgradeStopToFormat3(stop: stop, axis: axis) {
            guard let linked = format3LinkedValue(for: stop.value, axisTag: axis.tag) else { continue }
            let code = axis.tag == "ital" ? "ital_format1_upgrade" : "wght_format1_upgrade"
            let linkedLabel = format3LinkedLabel(axisTag: axis.tag, linkedValue: linked)
            let hint: String
            if axis.tag == "ital" {
                hint = "Format 3 expresses Roman↔Italic style linking without requiring a named stop at the linked value."
            } else {
                hint = "Format 3 expresses Regular↔Bold weight linking without requiring a named stop at the linked value."
            }
            warnings.append(
                PlanWarning(
                    code: code,
                    axis: axis.tag,
                    name: stop.name,
                    stopIDs: [stop.id],
                    message: "Axis '\(axis.tag)' stop “\(stop.name)” uses Format 1; Format 3 with link to \(linkedLabel) is recommended.",
                    hint: hint
                )
            )
        }
        return warnings
    }

    public static func shouldUpgradeStopToFormat3(stop: AxisValue, axis: AxisDefinition) -> Bool {
        guard stop.statFormat == 1 else { return false }
        return format3LinkedValue(for: stop.value, axisTag: axis.tag) != nil
    }

    public static func format3LinkedValue(for stopValue: Double, axisTag: String) -> Double? {
        switch axisTag {
        case "ital":
            if AxisCoordinate.valuesEqual(stopValue, 0) { return 1 }
            if AxisCoordinate.valuesEqual(stopValue, 1) { return 0 }
        case "wght":
            if AxisCoordinate.valuesEqual(stopValue, 400) { return 700 }
            if AxisCoordinate.valuesEqual(stopValue, 700) { return 400 }
        default:
            break
        }
        return nil
    }

    public static func format3LinkedLabel(axisTag: String, linkedValue: Double) -> String {
        switch axisTag {
        case "ital":
            return AxisCoordinate.valuesEqual(linkedValue, 0) ? "0 (Roman)" : "1 (Italic)"
        case "wght":
            return AxisCoordinate.valuesEqual(linkedValue, 400)
                ? "400 (Regular)"
                : "700 (Bold)"
        default:
            return AxisCoordinateFormat.format(linkedValue)
        }
    }

    // MARK: - Private

    private static func resolveLinkedTarget(for primary: AxisValue, in stops: [AxisValue]) -> AxisValue? {
        guard let linkedValue = primary.linkedValue else { return nil }
        return stops.first { candidate in
            candidate.id != primary.id
                && AxisCoordinate.valuesEqual(candidate.value, linkedValue)
        }
    }

    private static func isLinkedTarget(ofAnotherFormat3Stop stop: AxisValue, in stops: [AxisValue]) -> Bool {
        stops.contains { other in
            other.id != stop.id
                && other.statFormat == 3
                && other.linkedValue != nil
                && AxisCoordinate.valuesEqual(other.linkedValue!, stop.value)
        }
    }

    private static func formatValue(_ value: Double) -> String {
        AxisCoordinateFormat.format(value)
    }
}
