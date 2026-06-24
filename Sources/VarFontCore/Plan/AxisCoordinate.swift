import Foundation

/// OpenType axis coordinates are Fixed 16.16 values; exact `Double` equality is unsafe after parsing.
public enum AxisCoordinate {
    public static let tolerance = 0.001

    public static func valuesEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = tolerance) -> Bool {
        abs(lhs - rhs) < tolerance
    }

    public static func matchingStop(in values: [AxisValue], coordinate: Double) -> AxisValue? {
        values.first { valuesEqual($0.value, coordinate) }
    }
}
