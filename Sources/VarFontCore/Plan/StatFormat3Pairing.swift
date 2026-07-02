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
            if resolveLinkedTarget(for: stop, in: axis.values) == nil {
                warnings.append(
                    PlanWarning(
                        code: "orphan_stat_link",
                        axis: axis.tag,
                        stopIDs: [stop.id],
                        message: "Axis '\(axis.tag)' stop “\(stop.name)” links to missing value \(formatValue(linkedValue)).",
                        hint: "Add a stop at the linked coordinate or clear the link."
                    )
                )
            }
        }
        return warnings
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
