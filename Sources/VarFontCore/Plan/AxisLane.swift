import Foundation

/// UI / planning lane derived from axis role and fvar scale presence.
public enum AxisLane: String, Sendable, CaseIterable {
    case variation
    case pinned
    case registration
}

extension AxisDefinition {
    public var lane: AxisLane {
        switch role {
        case .instance:
            return .variation
        case .designRecordOnly:
            return .registration
        case .statOnly, .parametric:
            return hasFvarScale ? .pinned : .registration
        }
    }

    /// Coordinate pinned into every generated instance for non-grid axes; nil when not pinned.
    public var pinCoordinate: Double? {
        AxisPinPolicy.pinCoordinate(for: self)
    }
}
