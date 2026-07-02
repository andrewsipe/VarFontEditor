import Foundation

public enum RegistrationAxisSupport {
    public static func inferFileStatRegistration(axes: [AxisDefinition]) -> [String: Double] {
        var registration: [String: Double] = [:]
        for axis in axes where axis.isDesignRecordOnly {
            if let sole = axis.values.first {
                registration[axis.tag] = sole.value
            }
        }
        return registration
    }

    public static func registrationWarnings(
        font: FontDocument,
        analysis: FontAnalysis?
    ) -> [PlanWarning] {
        var warnings: [PlanWarning] = []
        let isItalicFile = analysis?.inferred.isItalicFont == true
            || font.sourcePath.localizedCaseInsensitiveContains("italic")

        for (tag, value) in font.fileStatRegistration {
            guard let axis = font.axes.first(where: { $0.tag == tag }),
                  axis.isDesignRecordOnly else { continue }
            guard let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: value) else {
                warnings.append(
                    PlanWarning(
                        code: "registration_value_missing",
                        axis: tag,
                        message: "Registration axis '\(tag)' resolves to \(AxisCoordinateFormat.format(value)) with no matching STAT stop.",
                        hint: "Pick a registration stop that exists on this axis."
                    )
                )
                continue
            }
            let isItalicRegistration = stop.name.localizedCaseInsensitiveContains("italic")
            if !isItalicFile && isItalicRegistration {
                warnings.append(
                    PlanWarning(
                        code: "registration_mismatch",
                        axis: tag,
                        name: stop.name,
                        message: "Upright file registers as “\(stop.name)” on axis '\(tag)'.",
                        hint: "Set this file's registration to Roman/upright or verify the source font."
                    )
                )
            }
        }
        return warnings
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
