import Foundation

enum NamingOrderInference {
    static let fallbackTags = ["wdth", "wght", "opsz", "slnt", "ital"]

    static func suggest(
        designAxes: [StatDesignAxis],
        additionalTags: [String] = []
    ) -> [String] {
        var order: [String] = []
        var seen = Set<String>()

        for axis in designAxes.sorted(by: { $0.ordering < $1.ordering }) {
            guard seen.insert(axis.tag).inserted else { continue }
            order.append(axis.tag)
        }

        for tag in fallbackTags where seen.insert(tag).inserted {
            order.append(tag)
        }

        for tag in additionalTags where seen.insert(tag).inserted {
            order.append(tag)
        }

        return order
    }
}
