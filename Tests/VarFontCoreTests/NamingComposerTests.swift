import XCTest
@testable import VarFontCore

final class NamingComposerTests: XCTestCase {
    func testComposeMatchesStopWithinTolerance() {
        let axis = AxisDefinition(
            tag: "wght",
            role: .instance,
            values: [
                AxisValue(id: "wght-a", value: 400, name: "Regular", elidable: false),
            ]
        )
        let naming = NamingPolicy(order: ["wght"], elidedFallback: "Fallback")

        let result = NamingComposer.compose(
            coords: ["wght": 399.9999999],
            axes: [axis],
            naming: naming
        )

        XCTAssertEqual(result.name, "Regular")
        XCTAssertEqual(result.chain.count, 1)
        XCTAssertEqual(result.chain[0].name, "Regular")
    }

    func testComposeFallsBackWhenNoStopMatches() {
        let axis = AxisDefinition(
            tag: "wght",
            role: .instance,
            values: [
                AxisValue(id: "wght-a", value: 400, name: "Regular", elidable: false),
            ]
        )
        let naming = NamingPolicy(order: ["wght"], elidedFallback: "Fallback")

        let result = NamingComposer.compose(
            coords: ["wght": 350],
            axes: [axis],
            naming: naming
        )

        XCTAssertEqual(result.name, "Fallback")
        XCTAssertTrue(result.chain.isEmpty)
    }
}

final class NamingOrderInferenceTests: XCTestCase {
    func testSuggestUsesSTATOrderingFirst() {
        let axes = [
            StatDesignAxis(tag: "wght", nameID: 1, ordering: 2),
            StatDesignAxis(tag: "opsz", nameID: 2, ordering: 0),
            StatDesignAxis(tag: "wdth", nameID: 3, ordering: 1),
        ]

        let order = NamingOrderInference.suggest(designAxes: axes)

        XCTAssertEqual(order.prefix(3), ["opsz", "wdth", "wght"])
    }

    func testSuggestAppendsFallbackTagsNotInSTAT() {
        let axes = [
            StatDesignAxis(tag: "opsz", nameID: 1, ordering: 0),
        ]

        let order = NamingOrderInference.suggest(designAxes: axes, additionalTags: ["ital"])

        XCTAssertTrue(order.contains("opsz"))
        XCTAssertTrue(order.contains("ital"))
        XCTAssertLessThan(order.firstIndex(of: "opsz")!, order.firstIndex(of: "ital")!)
    }
}
