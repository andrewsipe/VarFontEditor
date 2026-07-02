import Foundation

/// Shared inference for coordinates fixed on non-instance axes.
public enum AxisPinPolicy {
    public static func shouldPin(axis: AxisDefinition) -> Bool {
        axis.role != .instance && axis.role != .designRecordOnly
    }

    public static func pinCoordinate(for axis: AxisDefinition) -> Double? {
        guard shouldPin(axis: axis) else { return nil }
        if axis.values.count == 1, let value = axis.values.first?.value {
            return value
        }
        if let defaultValue = axis.default {
            return defaultValue
        }
        if let first = axis.values.first?.value {
            return first
        }
        return nil
    }

    public static func pinnedCoords(from axes: [AxisDefinition]) -> [String: Double] {
        var pinned: [String: Double] = [:]
        for axis in axes {
            guard let value = pinCoordinate(for: axis) else { continue }
            pinned[axis.tag] = value
        }
        return pinned
    }
}
