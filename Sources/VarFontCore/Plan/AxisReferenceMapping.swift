import Foundation

public enum ReferenceMappingKind: String, Codable, Sendable, CaseIterable {
    case identity
    case defaultAnchored = "default_anchored"
    case stopAnchored = "stop_anchored"
}

public struct ReferenceAnchor: Codable, Equatable, Sendable {
    public var reference: Double
    public var native: Double

    public init(reference: Double, native: Double) {
        self.reference = reference
        self.native = native
    }
}

/// Registry coordinate ladders and native ↔ reference conversion for **weight** and **width** only.
/// Optical size (`opsz`) always uses native designer coordinates — no registry translation.
public enum AxisReferenceMapping {
    public static func inferKind(for axis: AxisDefinition) -> ReferenceMappingKind {
        guard supportsReferenceLadder(axis.tag) else { return .identity }
        if isRegistryNativeAxis(axis) { return .identity }
        if inferAnchors(for: axis).count >= 2 { return .stopAnchored }
        if axis.default != nil || !axis.values.isEmpty { return .defaultAnchored }
        return .identity
    }

    public static func inferAnchors(for axis: AxisDefinition) -> [ReferenceAnchor] {
        guard supportsReferenceLadder(axis.tag) else { return [] }

        var anchors: [ReferenceAnchor] = []
        var seenNatives: Set<String> = []

        for stop in axis.values {
            guard let reference = inferReference(for: stop, axisTag: axis.tag) else { continue }
            let key = nativeKey(stop.value)
            guard !seenNatives.contains(key) else { continue }
            seenNatives.insert(key)
            anchors.append(ReferenceAnchor(reference: reference, native: stop.value))
        }

        return anchors.sorted { $0.native < $1.native }
    }

    public static func nativeToReference(_ native: Double, axis: AxisDefinition) -> Double {
        switch axis.referenceMapping ?? .identity {
        case .identity:
            return native
        case .defaultAnchored, .stopAnchored:
            return convertNativeToReference(native, axis: axis)
        }
    }

    public static func referenceToNative(_ reference: Double, axis: AxisDefinition) -> Double {
        switch axis.referenceMapping ?? .identity {
        case .identity:
            return reference
        case .defaultAnchored, .stopAnchored:
            return convertReferenceToNative(reference, axis: axis)
        }
    }

    public static func nextCanonicalReferenceStop(
        for axis: AxisDefinition,
        excluding values: [Double]
    ) -> Double? {
        guard let ladder = registryLadder(for: axis.tag) else { return nil }
        let used = Set(values.map { nativeToReference($0, axis: axis) })
        return ladder.first { candidate in
            !used.contains { AxisCoordinate.valuesEqual($0, candidate) }
        }
    }

    public static func registryLadder(for tag: String) -> [Double]? {
        canonicalLadder(for: tag)
    }

    public static func registryNormalReference(for tag: String) -> Double {
        switch tag {
        case "wght": 400
        case "wdth": 100
        default: 0
        }
    }

    /// True when native stop values already sit on the registry ladder (Roboto/Milgram-style).
    public static func isRegistryNativeAxis(_ axis: AxisDefinition) -> Bool {
        guard supportsReferenceLadder(axis.tag) else { return true }
        guard let min = axis.min, let max = axis.max else { return false }

        switch axis.tag {
        case "wght":
            if max > 925 || min < 99 { return true }
            if !axis.values.isEmpty {
                guard axis.values.allSatisfy({ referenceFromStopValue($0.value, tag: axis.tag) != nil }) else {
                    return false
                }
                return referenceFromStopValue(min, tag: axis.tag) != nil
                    && referenceFromStopValue(max, tag: axis.tag) != nil
            }
            return max <= 901
        case "wdth":
            if AxisCoordinate.valuesEqual(min, 50), max >= 150, max <= 201 {
                return true
            }
            if let defaultValue = axis.default, AxisCoordinate.valuesEqual(defaultValue, 100) {
                if !axis.values.isEmpty {
                    return axis.values.allSatisfy { referenceFromStopValue($0.value, tag: axis.tag) != nil }
                }
                return true
            }
            return false
        default:
            return true
        }
    }

    /// Weak name/value inference exposed for ladder anchoring (not primary display logic).
    public static func inferredRegistryReference(for stop: AxisValue, axisTag: String) -> Double? {
        inferReference(for: stop, axisTag: axisTag)
    }

    // MARK: - Private

    private static func supportsReferenceLadder(_ tag: String) -> Bool {
        tag == "wght" || tag == "wdth"
    }

    private static func canonicalLadder(for tag: String) -> [Double]? {
        switch tag {
        case "wght":
            return [100, 200, 300, 350, 400, 500, 600, 700, 800, 900]
        case "wdth":
            return [25, 50, 62.5, 75, 87.5, 100, 112.5, 125, 150, 200]
        default:
            return nil
        }
    }

    private static func registryLowReference(for tag: String) -> Double {
        switch tag {
        case "wght": 100
        case "wdth": 50
        default: 0
        }
    }

    private static func registryHighReference(for tag: String) -> Double {
        switch tag {
        case "wght": 900
        case "wdth": 200
        default: 100
        }
    }

    private static func inferReference(for stop: AxisValue, axisTag: String) -> Double? {
        if let fromValue = referenceFromStopValue(stop.value, tag: axisTag) {
            return fromValue
        }
        if stop.elidable {
            return registryNormalReference(for: axisTag)
        }
        if let fromName = referenceFromStopName(stop.name, tag: axisTag) {
            return fromName
        }
        return nil
    }

    private static func referenceFromStopValue(_ value: Double, tag: String) -> Double? {
        guard let ladder = canonicalLadder(for: tag) else { return nil }
        return ladder.first { AxisCoordinate.valuesEqual($0, value) }
    }

    private static func referenceFromStopName(_ name: String, tag: String) -> Double? {
        let key = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        switch tag {
        case "wght":
            let table: [(String, Double)] = [
                ("ultrablack", 900), ("fat", 900),
                ("black", 900), ("heavy", 900),
                ("extrabold", 800), ("exbold", 800), ("ultrabold", 800), ("xbold", 800),
                ("semibold", 600), ("demibold", 600),
                ("bold", 700),
                ("medium", 500),
                ("semilight", 350),
                ("extralight", 200), ("ultralight", 200),
                ("hair", 100), ("hairline", 100),
                ("thin", 100),
                ("light", 300),
                ("normal", 400), ("regular", 400),
            ]
            return table.first { key.contains($0.0) }?.1

        case "wdth":
            let table: [(String, Double)] = [
                ("ultraexpanded", 200), ("ultraexp", 200),
                ("extraexpanded", 150), ("extraexp", 150),
                ("expanded", 125), ("wide", 125),
                ("semiexpanded", 112.5), ("semiexp", 112.5),
                ("normal", 100), ("regular", 100),
                ("semicondensed", 87.5), ("semicond", 87.5),
                ("condensed", 75), ("cond", 75),
                ("extracondensed", 62.5), ("extracond", 62.5),
                ("ultracondensed", 50), ("ultracond", 50),
                ("supercondensed", 25), ("supercond", 25),
            ]
            return table.first { key.contains($0.0) }?.1

        default:
            return nil
        }
    }

    private static func convertNativeToReference(_ native: Double, axis: AxisDefinition) -> Double {
        let anchors = effectiveAnchors(for: axis)
        guard anchors.count >= 2 else { return native }
        return interpolate(
            native,
            in: anchors.map(\.native),
            out: anchors.map(\.reference)
        )
    }

    private static func convertReferenceToNative(_ reference: Double, axis: AxisDefinition) -> Double {
        let anchors = effectiveAnchors(for: axis)
        guard anchors.count >= 2 else { return reference }
        return interpolate(
            reference,
            in: anchors.map(\.reference),
            out: anchors.map(\.native)
        )
    }

    private static func effectiveAnchors(for axis: AxisDefinition) -> [ReferenceAnchor] {
        if axis.referenceMapping == .stopAnchored, axis.referenceAnchors.count >= 2 {
            return augmentedWithEndpoints(sortedAnchors(axis.referenceAnchors), axis: axis)
        }

        let inferred = inferAnchors(for: axis)
        if inferred.count >= 2 {
            return augmentedWithEndpoints(inferred, axis: axis)
        }

        return defaultAnchoredSyntheticAnchors(axis)
    }

    private static func defaultAnchoredSyntheticAnchors(_ axis: AxisDefinition) -> [ReferenceAnchor] {
        guard let min = axis.min, let max = axis.max else { return [] }

        let normalNative = axis.values.first(where: \.elidable)?.value
            ?? axis.values.first(where: {
                referenceFromStopName($0.name, tag: axis.tag) == registryNormalReference(for: axis.tag)
            })?.value
            ?? axis.default
            ?? min

        let refLow = registryLowReference(for: axis.tag)
        let refNormal = registryNormalReference(for: axis.tag)
        let refHigh = registryHighReference(for: axis.tag)

        if AxisCoordinate.valuesEqual(normalNative, min) {
            return [
                ReferenceAnchor(reference: refNormal, native: min),
                ReferenceAnchor(reference: refHigh, native: max),
            ]
        }

        return [
            ReferenceAnchor(reference: refLow, native: min),
            ReferenceAnchor(reference: refNormal, native: normalNative),
            ReferenceAnchor(reference: refHigh, native: max),
        ]
    }

    private static func augmentedWithEndpoints(
        _ anchors: [ReferenceAnchor],
        axis: AxisDefinition
    ) -> [ReferenceAnchor] {
        guard let min = axis.min, let max = axis.max else { return anchors }
        var result = sortedAnchors(anchors)

        if let first = result.first, first.native > min + 0.0001 {
            let reference = extrapolateReference(native: min, anchors: result, direction: .below)
                ?? registryLowReference(for: axis.tag)
            result.insert(ReferenceAnchor(reference: reference, native: min), at: 0)
        }

        if let last = result.last, last.native < max - 0.0001 {
            let reference = extrapolateReference(native: max, anchors: result, direction: .above)
                ?? registryHighReference(for: axis.tag)
            result.append(ReferenceAnchor(reference: reference, native: max))
        }

        return deduplicatedAnchors(result)
    }

    private enum ExtrapolationDirection {
        case below
        case above
    }

    private static func extrapolateReference(
        native: Double,
        anchors: [ReferenceAnchor],
        direction: ExtrapolationDirection
    ) -> Double? {
        guard anchors.count >= 2 else { return nil }
        switch direction {
        case .below:
            let a = anchors[0]
            let b = anchors[1]
            guard b.native > a.native else { return nil }
            let slope = (b.reference - a.reference) / (b.native - a.native)
            return a.reference + slope * (native - a.native)
        case .above:
            let a = anchors[anchors.count - 2]
            let b = anchors[anchors.count - 1]
            guard b.native > a.native else { return nil }
            let slope = (b.reference - a.reference) / (b.native - a.native)
            return b.reference + slope * (native - b.native)
        }
    }

    private static func sortedAnchors(_ anchors: [ReferenceAnchor]) -> [ReferenceAnchor] {
        anchors.sorted { $0.native < $1.native }
    }

    private static func deduplicatedAnchors(_ anchors: [ReferenceAnchor]) -> [ReferenceAnchor] {
        var seen: Set<String> = []
        var result: [ReferenceAnchor] = []
        for anchor in anchors {
            let key = nativeKey(anchor.native)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(anchor)
        }
        return result
    }

    private static func nativeKey(_ native: Double) -> String {
        String(format: "%.4f", native)
    }

    private static func interpolate(
        _ probe: Double,
        in input: [Double],
        out output: [Double]
    ) -> Double {
        guard input.count == output.count, input.count >= 2 else { return probe }
        if probe <= input[0] { return output[0] }
        if probe >= input[input.count - 1] { return output[output.count - 1] }
        for index in 0..<(input.count - 1) {
            let lowIn = input[index]
            let highIn = input[index + 1]
            if probe >= lowIn && probe <= highIn {
                let span = highIn - lowIn
                guard span > 0 else { return output[index] }
                let ratio = (probe - lowIn) / span
                return output[index] + ratio * (output[index + 1] - output[index])
            }
        }
        return probe
    }
}
