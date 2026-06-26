import Foundation
import VarFontCore

// MARK: - Inspector view models

enum InspectorOpenTypeSource: String, Sendable {
    case stat = "STAT"
    case fvar = "fvar"
    case name = "name"
    case planned = "planned"
}

enum InspectorOpenTypeRowKind: Sendable {
    case statAxisValue
    case fvarCoordinates
    case fvarSubfamilyNameID
    case nameSummary
    case deferredNote
}

struct InspectorOpenTypeRow: Identifiable, Sendable {
    var id: String
    var table: String
    var field: String
    var content: String
    var sources: [InspectorOpenTypeSource]
    var isDerived: Bool
    var kind: InspectorOpenTypeRowKind
}

struct InspectorAxisCoordRow: Identifiable, Sendable {
    var tag: String
    var value: Double
    var stopName: String
    /// Axis participates in the instance naming grid (not STAT-only).
    var participatesInNaming: Bool
    /// Stop label is elided from the composed style name.
    var isElided: Bool
    var stopID: String?
    /// Show elidable toggle for this instance's naming-chain stop.
    var showsElisionToggle: Bool
    var isElidable: Bool

    var id: String { tag }

    var isDimmed: Bool { !participatesInNaming || isElided }
}
