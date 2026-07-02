import Foundation

public struct LadderAlignmentIssue: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case missingIdealStop
        case misalignedStop
        case cannotAnchor
    }

    public var kind: Kind
    public var axisTag: String
    public var idealReference: Double?
    public var suggestedNative: Double?
    public var existingStopID: String?
    public var existingNative: Double?
    public var message: String
    public var hint: String?
}

/// Compares wght/wdth STAT stops against the OpenType registry ladder and recommends gaps or nudges.
/// Optical size (`opsz`) is intentionally excluded — designer point sizes stay native.
public enum AxisLadderAlignment {
    public static let supportedTags: Set<String> = ["wght", "wdth"]

    public static func supportsAlignment(_ tag: String) -> Bool {
        supportedTags.contains(tag)
    }

    public static func analyze(axis: AxisDefinition) -> [LadderAlignmentIssue] {
        guard supportsAlignment(axis.tag) else { return [] }
        guard !AxisReferenceMapping.isRegistryNativeAxis(axis) else { return [] }
        guard let min = axis.min, let max = axis.max else { return [] }

        guard nominalAnchor(for: axis) != nil else {
            return [
                LadderAlignmentIssue(
                    kind: .cannotAnchor,
                    axisTag: axis.tag,
                    message: "\(axis.displayName ?? axis.tag): mark a Regular/Normal stop as elidable to analyze registry alignment.",
                    hint: "Set the Regular width or weight stop as elidable, then review suggested gaps."
                ),
            ]
        }

        var issues: [LadderAlignmentIssue] = []
        var claimedStopIDs = Set<String>()
        let tolerance = matchTolerance(axis)

        for idealRef in achievableIdealReferences(for: axis) {
            guard let suggestedNative = suggestedNative(
                forIdeal: idealRef,
                axis: axis,
                min: min,
                max: max
            ) else {
                continue
            }

            if let match = nearestStop(
                to: suggestedNative,
                in: axis.values,
                tolerance: tolerance,
                excluding: claimedStopIDs
            ) {
                claimedStopIDs.insert(match.id)
                let mappedRef = AxisReferenceMapping.nativeToReference(match.value, axis: axis)
                if !AxisCoordinate.valuesEqual(mappedRef, idealRef),
                   !AxisCoordinate.valuesEqual(match.value, idealRef) {
                    issues.append(
                        LadderAlignmentIssue(
                            kind: .misalignedStop,
                            axisTag: axis.tag,
                            idealReference: idealRef,
                            suggestedNative: suggestedNative,
                            existingStopID: match.id,
                            existingNative: match.value,
                            message: "\(axis.displayName ?? axis.tag): “\(match.name)” at \(AxisStopSuggestions.formatValue(match.value)) — registry step \(AxisStopSuggestions.formatValue(idealRef)) expects ≈ \(AxisStopSuggestions.formatValue(suggestedNative)).",
                            hint: "Nudge the stop value or add a separate stop at the suggested native coordinate."
                        )
                    )
                }
                continue
            }

            issues.append(
                LadderAlignmentIssue(
                    kind: .missingIdealStop,
                    axisTag: axis.tag,
                    idealReference: idealRef,
                    suggestedNative: suggestedNative,
                    message: "\(axis.displayName ?? axis.tag): missing registry step \(AxisStopSuggestions.formatValue(idealRef)) (suggest native ≈ \(AxisStopSuggestions.formatValue(suggestedNative))).",
                    hint: "Add a STAT stop at the suggested native value."
                )
            )
        }

        return issues.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .missingIdealStop
            }
            return (lhs.idealReference ?? 0) < (rhs.idealReference ?? 0)
        }
    }

    public static func planWarnings(axes: [AxisDefinition]) -> [PlanWarning] {
        axes.flatMap { axis in
            analyze(axis: axis).map { issue in
                PlanWarning(
                    code: planWarningCode(for: issue.kind),
                    axis: issue.axisTag,
                    stopIDs: issue.existingStopID.map { [$0] },
                    message: issue.message,
                    hint: issue.hint
                )
            }
        }
    }

    // MARK: - Private

    private struct NominalAnchor {
        var native: Double
        var reference: Double
    }

    private static func planWarningCode(for kind: LadderAlignmentIssue.Kind) -> String {
        switch kind {
        case .missingIdealStop: "ladder_missing_stop"
        case .misalignedStop: "ladder_misaligned_stop"
        case .cannotAnchor: "ladder_cannot_anchor"
        }
    }

    private static func nominalAnchor(for axis: AxisDefinition) -> NominalAnchor? {
        let normalRef = AxisReferenceMapping.registryNormalReference(for: axis.tag)
        guard let elidable = axis.values.first(where: \.elidable) else { return nil }
        return NominalAnchor(native: elidable.value, reference: normalRef)
    }

    /// Registry ladder steps this axis can actually reach between fvar min and max.
    /// Steps outside the mapped span (e.g. wght 100–300 when min is 360) are excluded.
    private static func achievableIdealReferences(for axis: AxisDefinition) -> [Double] {
        guard let ladder = AxisReferenceMapping.registryLadder(for: axis.tag),
              let min = axis.min,
              let max = axis.max else { return [] }

        return ladder.filter { idealRef in
            let native = AxisReferenceMapping.referenceToNative(idealRef, axis: axis)
            guard native >= min - 0.0001, native <= max + 0.0001 else { return false }
            let roundTrip = AxisReferenceMapping.nativeToReference(native, axis: axis)
            return AxisCoordinate.valuesEqual(roundTrip, idealRef)
        }
    }

    private static func suggestedNative(
        forIdeal idealRef: Double,
        axis: AxisDefinition,
        min: Double,
        max: Double
    ) -> Double? {
        if AxisReferenceMapping.isRegistryNativeAxis(axis) {
            guard idealRef >= min - 0.0001, idealRef <= max + 0.0001 else { return nil }
            return idealRef
        }
        let native = AxisReferenceMapping.referenceToNative(idealRef, axis: axis)
        guard native >= min - 0.0001, native <= max + 0.0001 else { return nil }
        return native
    }

    private static func matchTolerance(_ axis: AxisDefinition) -> Double {
        guard let min = axis.min, let max = axis.max else { return 1 }
        return Swift.max(1, (max - min) * 0.03)
    }

    private static func nearestStop(
        to target: Double,
        in stops: [AxisValue],
        tolerance: Double,
        excluding claimedStopIDs: Set<String>
    ) -> AxisValue? {
        stops
            .filter { !claimedStopIDs.contains($0.id) }
            .min { lhs, rhs in
                abs(lhs.value - target) < abs(rhs.value - target)
            }
            .flatMap { candidate in
                abs(candidate.value - target) <= tolerance ? candidate : nil
            }
    }
}
