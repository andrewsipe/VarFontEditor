import Foundation

public enum RegistrationAxisSupport {
    public static func inferFileStatRegistration(
        axes: [AxisDefinition],
        analysis: FontAnalysis? = nil,
        sourcePath: String? = nil
    ) -> [String: Double] {
        var registration: [String: Double] = [:]
        for axis in axes where axis.isDesignRecordOnly {
            if let value = inferRegistrationValue(
                forTag: axis.tag,
                axes: axes,
                analysis: analysis,
                sourcePath: sourcePath,
                inferredIsItalicFile: analysis.map { isItalicFile(analysis: $0, sourcePath: sourcePath) }
            ) {
                registration[axis.tag] = value
            }
        }
        return registration
    }

    public static func inferRegistrationValue(
        forTag tag: String,
        axes: [AxisDefinition],
        analysis: FontAnalysis? = nil,
        sourcePath: String? = nil,
        inferredIsItalicFile: Bool? = nil
    ) -> Double? {
        guard let axis = axes.first(where: { $0.tag == tag }),
              axis.isDesignRecordOnly else { return nil }
        if let elidable = axis.values.first(where: \.elidable) {
            return elidable.value
        }
        if tag == "ital" {
            return inferItalRegistration(
                axis: axis,
                analysis: analysis,
                sourcePath: sourcePath,
                inferredIsItalicFile: inferredIsItalicFile
            )
        }
        if tag == "slnt" {
            return inferSlntRegistration(axis: axis, analysis: analysis)
        }
        return axis.values.first?.value
    }

    public static func isItalicFile(
        font: FontDocument,
        analysis: FontAnalysis? = nil
    ) -> Bool {
        if let inferred = font.inferredIsItalicFile { return inferred }
        return isItalicFile(analysis: analysis, sourcePath: font.sourcePath)
    }

    public static func isItalicFile(
        analysis: FontAnalysis?,
        sourcePath: String?
    ) -> Bool {
        analysis?.inferred.isItalicFont == true
            || (sourcePath?.localizedCaseInsensitiveContains("italic") ?? false)
            || (analysis?.source.fullName.localizedCaseInsensitiveContains("italic") ?? false)
    }

    public static func uprightStop(on axis: AxisDefinition) -> AxisValue? {
        axis.values.first { stop in
            let name = stop.name.lowercased()
            return name.contains("roman")
                || name.contains("upright")
                || name == "regular"
        }
    }

    public static func isUprightLikeStopName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("roman")
            || lowered.contains("upright")
            || lowered == "regular"
    }

    public static func isItalicLikeStopName(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("italic")
    }

    public static func correctedItalConventionValue(for stop: AxisValue) -> Double? {
        if isUprightLikeStopName(stop.name), !AxisCoordinate.valuesEqual(stop.value, 0) {
            return 0
        }
        if isItalicLikeStopName(stop.name), !AxisCoordinate.valuesEqual(stop.value, 1) {
            return 1
        }
        return nil
    }

    /// Counterpart coordinate for `ital` Format 3 style linking (0↔1).
    public static func italFormat3LinkedValue(for stopValue: Double) -> Double? {
        if AxisCoordinate.valuesEqual(stopValue, 0) { return 1 }
        if AxisCoordinate.valuesEqual(stopValue, 1) { return 0 }
        return nil
    }

    public static func shouldUpgradeItalStopToFormat3(stop: AxisValue, axis: AxisDefinition) -> Bool {
        guard axis.tag == "ital", axis.isDesignRecordOnly else { return false }
        guard stop.statFormat == 1 else { return false }
        return italFormat3LinkedValue(for: stop.value) != nil
    }

    public static func italFormat1UpgradeWarnings(font: FontDocument) -> [PlanWarning] {
        guard let axis = font.axes.first(where: { $0.tag == "ital" && $0.isDesignRecordOnly }) else { return [] }
        return StatFormat3Pairing.format1UpgradeWarnings(for: axis)
    }

    public static func allRegistrationPlanWarnings(
        font: FontDocument,
        analysis: FontAnalysis? = nil
    ) -> [PlanWarning] {
        registrationWarnings(font: font, analysis: analysis)
            + italConventionWarnings(font: font)
            + italFormat1UpgradeWarnings(font: font)
            + wghtFormat1UpgradeWarnings(font: font)
    }

    public static func wghtFormat1UpgradeWarnings(font: FontDocument) -> [PlanWarning] {
        guard let axis = font.axes.first(where: { $0.tag == "wght" && $0.role == .instance }) else { return [] }
        return StatFormat3Pairing.format1UpgradeWarnings(for: axis)
    }

    public static func registrationWarnings(
        font: FontDocument,
        analysis: FontAnalysis?
    ) -> [PlanWarning] {
        var warnings: [PlanWarning] = []
        let isItalicFile = isItalicFile(font: font, analysis: analysis)

        for (tag, value) in font.fileStatRegistration {
            guard let axis = font.axes.first(where: { $0.tag == tag }),
                  axis.isDesignRecordOnly else { continue }
            guard let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: value) else {
                warnings.append(
                    PlanWarning(
                        code: "registration_value_missing",
                        axis: tag,
                        message: "Registration axis '\(tag)' resolves to \(AxisCoordinateFormat.format(value)) with no matching STAT stop.",
                        hint: "Registration needs to point at a stop that actually exists on this axis."
                    )
                )
                continue
            }
            if !isItalicFile && isItalicLikeStopName(stop.name) {
                warnings.append(
                    PlanWarning(
                        code: "registration_mismatch",
                        axis: tag,
                        name: stop.name,
                        stopIDs: [stop.id],
                        message: "Upright file registers as “\(stop.name)” on axis '\(tag)'.",
                        hint: "Worth a look: either this file's registration can move to Roman/upright, or it's correct and the source font can be double-checked."
                    )
                )
            }
        }
        return warnings
    }

    public static func italConventionWarnings(font: FontDocument) -> [PlanWarning] {
        var warnings: [PlanWarning] = []
        for axis in font.axes where axis.tag == "ital" && axis.isDesignRecordOnly {
            for stop in axis.values {
                guard correctedItalConventionValue(for: stop) != nil else { continue }
                let expected = isUprightLikeStopName(stop.name) ? "0" : "1"
                warnings.append(
                    PlanWarning(
                        code: "ital_value_name_mismatch",
                        axis: axis.tag,
                        name: stop.name,
                        stopIDs: [stop.id],
                        message: "Axis 'ital' stop “\(stop.name)” uses value \(AxisCoordinateFormat.format(stop.value)); convention is \(expected).",
                        hint: "The usual `ital` convention would put this at a different value — or the current value can stay."
                    )
                )
            }
        }
        return warnings
    }

    private static func inferItalRegistration(
        axis: AxisDefinition,
        analysis: FontAnalysis?,
        sourcePath: String?,
        inferredIsItalicFile: Bool?
    ) -> Double {
        let isItalicFile = inferredIsItalicFile
            ?? isItalicFile(analysis: analysis, sourcePath: sourcePath)

        if isItalicFile {
            if let italic = axis.values.first(where: { isItalicLikeStopName($0.name) }) {
                return italic.value
            }
        } else if let upright = uprightStop(on: axis) {
            return upright.value
        }
        return axis.values.first?.value ?? 0
    }

    private static func inferSlntRegistration(
        axis: AxisDefinition,
        analysis: FontAnalysis?
    ) -> Double {
        if let angle = analysis?.inferred.postItalicAngle,
           let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: angle) {
            return stop.value
        }
        if let elidable = axis.values.first(where: \.elidable) {
            return elidable.value
        }
        if let upright = axis.values.first(where: { AxisCoordinate.valuesEqual($0.value, 0) }) {
            return upright.value
        }
        return axis.values.first?.value ?? 0
    }

    /// Clarifier categories superseded when this file has a matching design-record registration axis.
    public static func clarifierCategoriesCoveredByRegistration(font: FontDocument) -> Set<FileClarifierCategory> {
        clarifierCategoriesCoveredByRegistration(
            axes: font.axes,
            fileStatRegistration: font.fileStatRegistration
        )
    }

    public static func clarifierCategoriesCoveredByRegistration(
        axes: [AxisDefinition],
        fileStatRegistration: [String: Double]
    ) -> Set<FileClarifierCategory> {
        var covered = Set<FileClarifierCategory>()
        for tag in fileStatRegistration.keys {
            guard let axis = axes.first(where: { $0.tag == tag }),
                  axis.isDesignRecordOnly else { continue }
            switch tag {
            case "ital", "slnt": covered.insert(.slope)
            case "wdth": covered.insert(.width)
            case "opsz": covered.insert(.optical)
            default: break
            }
        }
        return covered
    }

    public static func registrationStopName(
        tag: String,
        axes: [AxisDefinition],
        fileStatRegistration: [String: Double]
    ) -> (stop: AxisValue, elided: Bool)? {
        guard let axis = axes.first(where: { $0.tag == tag }),
              axis.isDesignRecordOnly,
              let value = fileStatRegistration[tag],
              let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: value) else {
            return nil
        }
        return (stop, stop.elidable)
    }
}
