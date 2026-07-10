import Foundation

/// Compares project axis scales against the source font's fvar design space.
public enum FvarDesignSpaceAudit {
    public struct Divergence: Equatable, Sendable {
        public var axisTag: String
        public var field: String
        public var sourceValue: Double
        public var projectValue: Double

        public init(axisTag: String, field: String, sourceValue: Double, projectValue: Double) {
            self.axisTag = axisTag
            self.field = field
            self.sourceValue = sourceValue
            self.projectValue = projectValue
        }
    }

    public static func divergences(analysis: FontAnalysis, font: FontDocument) -> [Divergence] {
        let sourceByTag = Dictionary(
            uniqueKeysWithValues: analysis.axes
                .filter { $0.roleInferred != .designRecordOnly }
                .map { ($0.tag, $0) }
        )
        var result: [Divergence] = []
        for axis in font.axes where axis.hasFvarScale {
            guard let source = sourceByTag[axis.tag] else { continue }
            if let projectDefault = axis.default,
               !AxisCoordinate.valuesEqual(projectDefault, source.default) {
                result.append(
                    Divergence(
                        axisTag: axis.tag,
                        field: "default",
                        sourceValue: source.default,
                        projectValue: projectDefault
                    )
                )
            }
            if let projectMin = axis.min,
               !AxisCoordinate.valuesEqual(projectMin, source.min) {
                result.append(
                    Divergence(
                        axisTag: axis.tag,
                        field: "min",
                        sourceValue: source.min,
                        projectValue: projectMin
                    )
                )
            }
            if let projectMax = axis.max,
               !AxisCoordinate.valuesEqual(projectMax, source.max) {
                result.append(
                    Divergence(
                        axisTag: axis.tag,
                        field: "max",
                        sourceValue: source.max,
                        projectValue: projectMax
                    )
                )
            }
        }
        return result.sorted {
            $0.axisTag == $1.axisTag ? $0.field < $1.field : $0.axisTag < $1.axisTag
        }
    }

    /// Informational copy for Save Review — not actionable fixes.
    public static func informationalMessages(analysis: FontAnalysis, font: FontDocument) -> [String] {
        divergences(analysis: analysis, font: font).map { divergence in
            let source = AxisCoordinateFormat.format(divergence.sourceValue)
            let project = AxisCoordinateFormat.format(divergence.projectValue)
            return "\(divergence.axisTag) \(divergence.field) in this project (\(project)) differs from the source font (\(source)). fvar design space is not rewritten on save."
        }
    }
}
