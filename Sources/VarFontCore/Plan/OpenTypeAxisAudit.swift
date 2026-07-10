import Foundation

/// OpenType spec conformance checks for fvar/STAT parity, registered axes, and instance policy.
public enum OpenTypeAxisAudit {
    // MARK: - Plan warnings

    public static func planWarnings(
        font: FontDocument,
        instances: [PlannedInstance],
        namingOrder: [String] = []
    ) -> [PlanWarning] {
        var warnings: [PlanWarning] = []
        warnings.append(contentsOf: fvarStatParityWarnings(font: font))
        warnings.append(contentsOf: italSlntCoexistenceWarnings(font: font, namingOrder: namingOrder))
        warnings.append(contentsOf: defaultInstanceWarnings(font: font, instances: instances))
        warnings.append(contentsOf: opszFormat2SuggestWarnings(font: font))
        return warnings
    }

    // MARK: - Save review (informational)

    public static func informationalMessages(
        analysis: FontAnalysis,
        font: FontDocument
    ) -> [String] {
        registeredDefaultMessages(analysis: analysis, font: font)
    }

    public static func allInformationalMessages(
        analysis: FontAnalysis,
        font: FontDocument
    ) -> [String] {
        FvarDesignSpaceAudit.informationalMessages(analysis: analysis, font: font)
            + informationalMessages(analysis: analysis, font: font)
    }

    // MARK: - fvar ↔ STAT parity

    public static func fvarStatParityWarnings(font: FontDocument) -> [PlanWarning] {
        let statTags = Set(font.statDesignAxisTags)
        guard !statTags.isEmpty else { return [] }

        let fvarTags = Set(font.axes.filter(\.hasFvarScale).map(\.tag))
        var warnings: [PlanWarning] = []

        for tag in fvarTags.subtracting(statTags).sorted() {
            warnings.append(
                PlanWarning(
                    code: "fvar_missing_from_stat",
                    axis: tag,
                    message: "fvar axis '\(tag)' has no matching STAT DesignAxisRecord.",
                    hint: "Every fvar axis must appear in STAT. The source font may need repair outside this tool."
                )
            )
        }

        for tag in statTags.subtracting(fvarTags).sorted() {
            guard let axis = font.axes.first(where: { $0.tag == tag }) else {
                warnings.append(
                    PlanWarning(
                        code: "stat_missing_from_fvar",
                        axis: tag,
                        message: "STAT design axis '\(tag)' has no matching fvar axis record.",
                        hint: "Registration-only axes (e.g. ital) are expected; variation axes should exist in both tables."
                    )
                )
                continue
            }
            if axis.isDesignRecordOnly { continue }
            if axis.role == .statOnly || axis.role == .parametric { continue }
            warnings.append(
                PlanWarning(
                    code: "stat_missing_from_fvar",
                    axis: tag,
                    message: "STAT design axis '\(tag)' has no matching fvar axis record.",
                    hint: "Variation axes should exist in both fvar and STAT DesignAxisRecord."
                )
            )
        }

        return warnings
    }

    // MARK: - ital + slnt

    public static func italSlntCoexistenceWarnings(
        font: FontDocument,
        namingOrder: [String]
    ) -> [PlanWarning] {
        guard let italAxis = font.axes.first(where: { $0.tag == "ital" }),
              font.axes.contains(where: { $0.tag == "slnt" }) else { return [] }

        // slnt for slope variation + ital as STAT registration-only (no fvar scale) is intentional.
        if italAxis.isDesignRecordOnly && italAxis.role != .instance {
            return []
        }

        let slntInGrid = font.axes.contains { $0.tag == "slnt" && $0.role == .instance }
        let italInGrid = italAxis.role == .instance
        let bothInNaming = namingOrder.contains("ital") && namingOrder.contains("slnt")
        guard italInGrid || slntInGrid || bothInNaming else {
            return []
        }

        return [
            PlanWarning(
                code: "ital_slnt_coexistence",
                message: "Both 'ital' and 'slnt' appear in this font; registered axes should rarely use both.",
                hint: "Prefer one slope model when both axes vary instances: ital for true italic, slnt for oblique. Choose Don't change if this family intentionally uses both."
            ),
        ]
    }

    // MARK: - Default instance

    public static func defaultInstanceWarnings(
        font: FontDocument,
        instances: [PlannedInstance]
    ) -> [PlanWarning] {
        guard let coords = defaultInstanceCoordinates(font: font) else {
            if let message = defaultNotRepresentedInGridMessage(font: font) {
                return [
                    PlanWarning(
                        code: "default_instance_not_in_grid",
                        message: message,
                        hint: "The fvar default coordinate must be reachable from instance-axis stops (and pinned axes)."
                    ),
                ]
            }
            return []
        }

        let key = InstanceKeyBuilder.makeKey(coords: coords)
        guard let match = instances.first(where: { $0.key == key }) else {
            return [
                PlanWarning(
                    code: "default_instance_not_in_grid",
                    keys: [key],
                    message: "No instance grid row matches the fvar default coordinates.",
                    hint: "Add stops so the default-coordinate tuple is part of the instance grid."
                ),
            ]
        }

        guard match.included else {
            return [
                PlanWarning(
                    code: "default_instance_excluded",
                    keys: [key],
                    message: "The fvar default instance is excluded from the save plan.",
                    hint: "Include the default-coordinate instance so named instances cover the font's resting position."
                ),
            ]
        }

        return []
    }

    public static func defaultInstanceCoordinates(font: FontDocument) -> [String: Double]? {
        var coords = AxisPinPolicy.pinnedCoords(from: font.axes)

        for axis in font.axes where axis.role == .instance {
            guard let defaultValue = axis.default else { return nil }
            if let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: defaultValue) {
                coords[axis.tag] = stop.value
            } else if axis.values.contains(where: { AxisCoordinate.valuesEqual($0.value, defaultValue) }) {
                coords[axis.tag] = defaultValue
            } else {
                return nil
            }
        }

        guard !coords.isEmpty else { return nil }
        return coords
    }

    // MARK: - opsz Format 2

    public static func opszFormat2SuggestWarnings(font: FontDocument) -> [PlanWarning] {
        var warnings: [PlanWarning] = []
        for axis in font.axes where axis.tag == "opsz" {
            let discreteFormat1 = axis.values.filter { $0.statFormat == 1 }
            guard discreteFormat1.count >= 2 else { continue }
            warnings.append(
                PlanWarning(
                    code: "opsz_format2_suggest",
                    axis: axis.tag,
                    stopIDs: discreteFormat1.map(\.id),
                    message: "Axis 'opsz' has multiple discrete Format 1 stops; Format 2 ranges can express optical-size ranges more clearly.",
                    hint: "Optional suggestion only — keep Format 1 stops if they match your intent."
                )
            )
        }
        return warnings
    }

    // MARK: - Registered defaults (informational)

    private static let requiredDefaults: [String: Double] = [
        "wght": 400,
        "wdth": 100,
        "slnt": 0,
        "ital": 0,
    ]

    private static let opszRecommendedRange = 10.0...16.0

    public static func registeredDefaultMessages(
        analysis: FontAnalysis,
        font: FontDocument
    ) -> [String] {
        var messages: [String] = []
        let sourceByTag = Dictionary(uniqueKeysWithValues: analysis.axes.map { ($0.tag, $0) })

        for axis in font.axes where axis.hasFvarScale {
            guard let source = sourceByTag[axis.tag] else { continue }
            let actual = source.default

            if let required = requiredDefaults[axis.tag],
               !AxisCoordinate.valuesEqual(actual, required) {
                messages.append(
                    "\(axis.tag) fvar default is \(AxisCoordinateFormat.format(actual)); "
                        + "registry requires \(AxisCoordinateFormat.format(required)). "
                        + "fvar design space is not rewritten on save."
                )
            }

            if axis.tag == "opsz", !opszRecommendedRange.contains(actual) {
                messages.append(
                    "opsz fvar default is \(AxisCoordinateFormat.format(actual)); "
                        + "registry recommends 10–16 for typical text. "
                        + "fvar design space is not rewritten on save."
                )
            }
        }

        if let slntAxis = analysis.axes.first(where: { $0.tag == "slnt" }),
           let postAngle = analysis.inferred.postItalicAngle,
           !AxisCoordinate.valuesEqual(slntAxis.default, postAngle) {
            messages.append(
                "slnt fvar default (\(AxisCoordinateFormat.format(slntAxis.default))) "
                    + "differs from post.italicAngle (\(AxisCoordinateFormat.format(postAngle))). "
                    + "post table is not updated on save."
            )
        }

        return messages
    }

    // MARK: - Private

    private static func defaultNotRepresentedInGridMessage(font: FontDocument) -> String? {
        for axis in font.axes where axis.role == .instance {
            guard let defaultValue = axis.default else { continue }
            let represented = axis.values.contains { AxisCoordinate.valuesEqual($0.value, defaultValue) }
            if !represented {
                return "Instance axis '\(axis.tag)' has no stop at the fvar default (\(AxisCoordinateFormat.format(defaultValue)))."
            }
        }
        return nil
    }
}
