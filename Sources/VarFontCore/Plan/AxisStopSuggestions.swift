import Foundation

public enum AxisStopSuggestions {
    public static func suggestedValue(
        for axis: AxisDefinition,
        excludingStopIDs: Set<String> = []
    ) -> Double {
        let existing = axis.values
            .filter { !excludingStopIDs.contains($0.id) }
            .map(\.value)
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

    public static func formatValue(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        var text = String(value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }
}
