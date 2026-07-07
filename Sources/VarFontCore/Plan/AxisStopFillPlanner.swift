import Foundation

public enum AxisStopFillMode: String, Sendable, CaseIterable {
    case evenCount = "even_count"
    case fixedInterval = "fixed_interval"
}

public struct AxisStopFillOptions: Sendable, Equatable {
    public var axisTag: String
    public var displayName: String
    public var minValue: Double
    public var maxValue: Double
    public var countRange: ClosedRange<Int>
    public var recommendedCounts: [Int]
    public var defaultCount: Int
    public var intervalRange: ClosedRange<Double>
    public var defaultInterval: Double

    public init(
        axisTag: String,
        displayName: String,
        minValue: Double,
        maxValue: Double,
        countRange: ClosedRange<Int>,
        recommendedCounts: [Int],
        defaultCount: Int,
        intervalRange: ClosedRange<Double>,
        defaultInterval: Double
    ) {
        self.axisTag = axisTag
        self.displayName = displayName
        self.minValue = minValue
        self.maxValue = maxValue
        self.countRange = countRange
        self.recommendedCounts = recommendedCounts
        self.defaultCount = defaultCount
        self.intervalRange = intervalRange
        self.defaultInterval = defaultInterval
    }
}

public enum AxisStopFillPlanner {
    public static let suggestedCounts = [3, 6, 9, 12]
    public static let maxStopCount = 12
    public static let minStopCount = 2

    public static func options(for axis: AxisDefinition) -> AxisStopFillOptions? {
        guard axis.role == .instance,
              !axis.isDesignRecordOnly,
              axis.values.isEmpty,
              let minV = axis.min,
              let maxV = axis.max,
              maxV > minV else { return nil }

        let countRange = evenCountRange(min: minV, max: maxV)
        let recommended = recommendedCounts(min: minV, max: maxV, within: countRange)
        let defaultCount = defaultRecommendedCount(from: recommended, range: countRange)
        let intervalRange = Self.intervalRange(min: minV, max: maxV)
        let defaultInterval = defaultIntervalStep(
            min: minV,
            max: maxV,
            preferredCount: defaultCount,
            range: intervalRange
        )

        return AxisStopFillOptions(
            axisTag: axis.tag,
            displayName: axis.displayName ?? axis.tag,
            minValue: minV,
            maxValue: maxV,
            countRange: countRange,
            recommendedCounts: recommended,
            defaultCount: defaultCount,
            intervalRange: intervalRange,
            defaultInterval: defaultInterval
        )
    }

    public static func values(for axis: AxisDefinition, count: Int) -> [Double]? {
        AxisStopSuggestions.evenlySpacedValues(for: axis, count: count)
    }

    public static func values(for axis: AxisDefinition, interval: Double) -> [Double]? {
        AxisStopSuggestions.steppedValues(for: axis, step: interval)
    }

    public static func previewLabel(for values: [Double]) -> String {
        values.map { AxisStopSuggestions.formatValue($0) }.joined(separator: ", ")
    }

    // MARK: - Private

    private static func evenCountRange(min minV: Double, max maxV: Double) -> ClosedRange<Int> {
        let upper = min(maxStopCount, maxDistinctEvenCount(min: minV, max: maxV))
        return minStopCount...max(minStopCount, upper)
    }

    private static func maxDistinctEvenCount(min minV: Double, max maxV: Double) -> Int {
        var count = minStopCount
        while count < maxStopCount {
            let next = count + 1
            let current = evenlySpacedValues(min: minV, max: maxV, count: count)
            let candidate = evenlySpacedValues(min: minV, max: maxV, count: next)
            if current == candidate { break }
            count = next
        }
        return count
    }

    private static func recommendedCounts(
        min minV: Double,
        max maxV: Double,
        within range: ClosedRange<Int>
    ) -> [Int] {
        suggestedCounts.filter { count in
            range.contains(count)
                && evenlySpacedValues(min: minV, max: maxV, count: count).count == count
        }
    }

    private static func defaultRecommendedCount(
        from recommended: [Int],
        range: ClosedRange<Int>
    ) -> Int {
        if recommended.contains(6) { return 6 }
        if let first = recommended.first { return first }
        return range.upperBound
    }

    private static func intervalRange(min minV: Double, max maxV: Double) -> ClosedRange<Double> {
        let range = maxV - minV
        let minStep = max(range / Double(maxStopCount - 1), 0.001)
        let maxStep = range
        return minStep...maxStep
    }

    private static func defaultIntervalStep(
        min minV: Double,
        max maxV: Double,
        preferredCount: Int,
        range: ClosedRange<Double>
    ) -> Double {
        let rangeSpan = maxV - minV
        let evenStep = rangeSpan / Double(max(preferredCount - 1, 1))
        let snapped = snapInterval(evenStep, within: range)
        if let stepped = steppedValues(min: minV, max: maxV, step: snapped),
           stepped.count >= minStopCount {
            return snapped
        }
        return snapInterval(range.lowerBound, within: range)
    }

    private static func snapInterval(_ step: Double, within range: ClosedRange<Double>) -> Double {
        let clamped = min(max(step, range.lowerBound), range.upperBound)
        return AxisCoordinateFormat.canonical(clamped)
    }

    private static func evenlySpacedValues(min minV: Double, max maxV: Double, count: Int) -> [Double] {
        guard count >= 2, maxV > minV else { return [] }
        var values: [Double] = []
        for index in 0..<count {
            let fraction = Double(index) / Double(count - 1)
            values.append(AxisCoordinateFormat.canonical(minV + (maxV - minV) * fraction))
        }
        return deduplicatedSorted(values)
    }

    private static func steppedValues(min minV: Double, max maxV: Double, step: Double) -> [Double]? {
        var axis = AxisDefinition(tag: "tmp", min: minV, default: minV, max: maxV, role: .instance)
        return AxisStopSuggestions.steppedValues(for: axis, step: step)
    }

    private static func deduplicatedSorted(_ values: [Double]) -> [Double] {
        var result: [Double] = []
        for value in values {
            if !result.contains(where: { AxisCoordinate.valuesEqual($0, value) }) {
                result.append(value)
            }
        }
        return result.sorted()
    }
}
