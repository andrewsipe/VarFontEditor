import Foundation

public enum AxisStopValidator {
    public static func validate(axes: [AxisDefinition]) -> [PlanWarning] {
        var warnings: [PlanWarning] = []
        for axis in axes {
            warnings.append(contentsOf: duplicateValueWarnings(for: axis))
            warnings.append(contentsOf: StatFormat3Pairing.orphanLinkWarnings(for: axis))
            if axis.role == .instance {
                warnings.append(contentsOf: duplicateNameWarnings(for: axis))
            }
        }
        return warnings
    }

    // MARK: - Private

    private static func duplicateValueWarnings(for axis: AxisDefinition) -> [PlanWarning] {
        var groups: [Double: [AxisValue]] = [:]
        for stop in axis.values {
            if let existingKey = groups.keys.first(where: { AxisCoordinate.valuesEqual($0, stop.value) }) {
                groups[existingKey, default: []].append(stop)
            } else {
                groups[stop.value] = [stop]
            }
        }

        return groups.values.compactMap { stops in
            guard stops.count > 1 else { return nil }
            let label = axisLabel(axis)
            let valueText = formatValue(stops[0].value)
            let names = stops.map(\.name).joined(separator: "”, “")
            return PlanWarning(
                code: "duplicate_stop_value",
                axis: axis.tag,
                name: valueText,
                stopIDs: stops.map(\.id),
                message: "\(label) has \(stops.count) stops at value \(valueText) (“\(names)”).",
                hint: "Remove one stop or change a value so each stop on this axis is unique."
            )
        }
    }

    private static func duplicateNameWarnings(for axis: AxisDefinition) -> [PlanWarning] {
        var groups: [String: [AxisValue]] = [:]
        for stop in axis.values {
            groups[stop.name, default: []].append(stop)
        }

        return groups.compactMap { name, stops in
            guard stops.count > 1 else { return nil }
            let contributing = stops.filter { !$0.elidable }
            guard contributing.count > 1 else { return nil }
            let label = axisLabel(axis)
            let valueList = stops.map { "\(formatValue($0.value))" }.joined(separator: ", ")
            return PlanWarning(
                code: "duplicate_stop_name",
                axis: axis.tag,
                name: name,
                stopIDs: stops.map(\.id),
                message: "\(label) has \(stops.count) stops named “\(name)” at values \(valueList).",
                hint: "Rename one stop, remove a stop, or change elision so only one contributes to composed names."
            )
        }
    }

    private static func axisLabel(_ axis: AxisDefinition) -> String {
        if let displayName = axis.displayName, !displayName.isEmpty {
            return "\(displayName) (\(axis.tag))"
        }
        return "Axis \(axis.tag)"
    }

    private static func formatValue(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        var text = String(value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }
}
