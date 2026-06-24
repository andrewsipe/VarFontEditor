import Foundation

public enum NamingComposer {
    public struct Link: Equatable, Sendable {
        public var tag: String
        public var name: String
        public var elided: Bool
    }

    /// Compose a style name from axis stops using naming order and elision rules.
    public static func compose(
        coords: [String: Double],
        axes: [AxisDefinition],
        naming: NamingPolicy
    ) -> (name: String, chain: [Link]) {
        let axisByTag = Dictionary(uniqueKeysWithValues: axes.map { ($0.tag, $0) })
        var chain: [Link] = []
        var parts: [String] = []

        for tag in naming.order {
            guard let value = coords[tag] else { continue }
            guard let axis = axisByTag[tag] else { continue }
            guard let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: value) else { continue }

            let elided = stop.elidable
            chain.append(Link(tag: tag, name: stop.name, elided: elided))
            if !elided {
                parts.append(stop.name)
            }
        }

        let name = parts.isEmpty ? naming.elidedFallback : parts.joined(separator: " ")
        return (name, chain)
    }
}
