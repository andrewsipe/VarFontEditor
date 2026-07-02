import Foundation

public enum NamingComposer {
    public struct Link: Equatable, Sendable {
        public var kind: NamingChainLink.Kind
        public var tag: String
        public var name: String
        public var elided: Bool

        public init(kind: NamingChainLink.Kind = .axis, tag: String, name: String, elided: Bool) {
            self.kind = kind
            self.tag = tag
            self.name = name
            self.elided = elided
        }
    }

    /// Compose a style name from axis stops and per-file clarifiers using full naming order.
    public static func compose(
        coords: [String: Double],
        axes: [AxisDefinition],
        naming: NamingPolicy,
        fileRole: FileRole? = nil,
        fileStatRegistration: [String: Double] = [:]
    ) -> (name: String, chain: [Link]) {
        let axisByTag = Dictionary(uniqueKeysWithValues: axes.map { ($0.tag, $0) })
        var chain: [Link] = []
        var parts: [String] = []

        for token in naming.order {
            if NamingToken.isClarifier(token) {
                guard let category = NamingToken.clarifierCategory(for: token),
                      let label = fileRole?.label(for: category),
                      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                if token == NamingPolicy.clarifierTokenSlope,
                   fileStatRegistration["ital"] != nil,
                   axisByTag["ital"]?.isDesignRecordOnly == true {
                    continue
                }
                chain.append(Link(kind: .clarifier, tag: token, name: label, elided: false))
                parts.append(label)
                continue
            }

            if let axis = axisByTag[token], axis.isDesignRecordOnly {
                guard let resolved = RegistrationAxisSupport.registrationStopName(
                    tag: token,
                    axes: axes,
                    fileStatRegistration: fileStatRegistration
                ) else { continue }
                chain.append(Link(kind: .axis, tag: token, name: resolved.stop.name, elided: resolved.elided))
                if !resolved.elided {
                    parts.append(resolved.stop.name)
                }
                continue
            }

            guard let value = coords[token] else { continue }
            guard let axis = axisByTag[token] else { continue }
            guard axis.role == .instance else { continue }
            guard let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: value) else { continue }

            let elided = stop.elidable
            chain.append(Link(kind: .axis, tag: token, name: stop.name, elided: elided))
            if !elided {
                parts.append(stop.name)
            }
        }

        let fallback = fileRole?.elidedFallbackOverride ?? naming.elidedFallback
        let name = parts.isEmpty ? fallback : parts.joined(separator: " ")
        return (name, chain)
    }
}
