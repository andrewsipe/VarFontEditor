import Foundation

public enum AxisStopSuggestions {
    public static func suggestedValue(
        for axis: AxisDefinition,
        excludingStopIDs: Set<String> = [],
        excludingValues: [Double] = []
    ) -> Double {
        let existing = axis.values
            .filter { !excludingStopIDs.contains($0.id) }
            .map(\.value) + excludingValues
        let minV = axis.min ?? axis.default ?? existing.min() ?? 0
        let maxV = axis.max ?? axis.default ?? existing.max() ?? minV

        func isTaken(_ candidate: Double) -> Bool {
            existing.contains { AxisCoordinate.valuesEqual($0, candidate) }
        }

        func inRange(_ candidate: Double) -> Bool {
            candidate >= minV - 0.0001 && candidate <= maxV + 0.0001
        }

        if (axis.referenceMapping ?? .identity) != .identity,
           let reference = AxisReferenceMapping.nextCanonicalReferenceStop(
               for: axis,
               excluding: existing
           ) {
            let native = AxisReferenceMapping.referenceToNative(reference, axis: axis)
            if inRange(native), !isTaken(native) {
                return AxisCoordinateFormat.canonical(native)
            }
        }

        if existing.isEmpty {
            let seed = axis.default ?? minV
            if !isTaken(seed), inRange(seed) { return seed }
        }

        var candidates: [Double] = []

        if let first = existing.min(), first > minV {
            candidates.append((minV + first) / 2)
        }

        let sorted = existing.sorted()
        for index in 0..<(sorted.count - 1) {
            let lower = sorted[index]
            let upper = sorted[index + 1]
            if upper > lower {
                candidates.append((lower + upper) / 2)
            }
        }

        if let last = sorted.last, last < maxV {
            candidates.append((last + maxV) / 2)
            let step: Double = {
                guard sorted.count >= 2 else { return 1 }
                let delta = sorted[sorted.count - 1] - sorted[sorted.count - 2]
                return delta > 0 ? delta : 1
            }()
            var probe = last + step
            while probe < maxV {
                candidates.append(probe)
                probe += step
            }
        }

        for candidate in candidates {
            if inRange(candidate), !isTaken(candidate) {
                return candidate
            }
        }

        var scan = minV
        while scan <= maxV {
            if !isTaken(scan) { return scan }
            scan += 1
        }

        return axis.default ?? minV
    }

    public static func formatValue(_ rawValue: Double) -> String {
        // Round through the canonical 2-decimal representation first — callers may pass raw
        // slider/drag values (e.g. 165.45454545454547 from a repeating-decimal division) that
        // would otherwise print with full floating-point precision.
        let value = AxisCoordinateFormat.canonical(rawValue)
        if value.rounded() == value {
            return String(Int(value))
        }
        var text = String(value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    /// Evenly spaced stops from axis `min` through `max` (inclusive). Requires at least two stops.
    public static func evenlySpacedValues(for axis: AxisDefinition, count: Int) -> [Double]? {
        guard count >= 2,
              let minV = axis.min,
              let maxV = axis.max,
              maxV > minV else { return nil }

        var values: [Double] = []
        for index in 0..<count {
            let fraction = Double(index) / Double(count - 1)
            values.append(AxisCoordinateFormat.canonical(minV + (maxV - minV) * fraction))
        }
        return deduplicatedSorted(values)
    }

    /// Stops at a fixed interval from a grid-aligned start through `max` (e.g. 0, 100, 200).
    public static func steppedValues(for axis: AxisDefinition, step: Double) -> [Double]? {
        guard step > 0,
              let minV = axis.min,
              let maxV = axis.max,
              maxV >= minV else { return nil }

        let start: Double = (minV <= 0 && 0 <= maxV) ? 0 : minV
        var values: [Double] = []
        var value = start
        while value <= maxV + 0.0001 {
            if value >= minV - 0.0001 {
                values.append(AxisCoordinateFormat.canonical(value))
            }
            value += step
        }
        let deduped = deduplicatedSorted(values)
        return deduped.count >= 2 ? deduped : nil
    }

    /// Round step for interval fills (e.g. 0–200 → 100).
    public static func suggestedIntervalStep(for axis: AxisDefinition) -> Double? {
        guard let minV = axis.min,
              let maxV = axis.max,
              maxV > minV else { return nil }
        let range = maxV - minV
        guard range > 0 else { return nil }
        let magnitude = pow(10.0, floor(log10(range)))
        return magnitude >= 1 ? magnitude : range / 2
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
