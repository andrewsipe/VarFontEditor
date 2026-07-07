import XCTest
@testable import VarFontCore

final class AxisStopFillPlannerTests: XCTestCase {
    private func weightAxis(min: Double, max: Double) -> AxisDefinition {
        AxisDefinition(tag: "wght", min: min, default: min, max: max, role: .instance, values: [])
    }

    func testOptionsForZeroToTwoHundred() throws {
        let axis = weightAxis(min: 0, max: 200)
        let options = try XCTUnwrap(AxisStopFillPlanner.options(for: axis))
        XCTAssertEqual(options.countRange, 2...12)
        XCTAssertEqual(options.recommendedCounts, [3, 6, 9, 12])
        XCTAssertEqual(options.defaultCount, 6)
        XCTAssertEqual(
            try XCTUnwrap(AxisStopFillPlanner.values(for: axis, count: 6)),
            [0, 40, 80, 120, 160, 200]
        )
        XCTAssertEqual(
            try XCTUnwrap(AxisStopFillPlanner.values(for: axis, interval: 100)),
            [0, 100, 200]
        )
    }

    func testEvenCountFiveMatchesEnds() throws {
        let axis = weightAxis(min: 0, max: 200)
        XCTAssertEqual(
            try XCTUnwrap(AxisStopFillPlanner.values(for: axis, count: 5)),
            [0, 50, 100, 150, 200]
        )
    }

    func testNarrowRangeLimitsSuggestedCounts() throws {
        let axis = weightAxis(min: 0, max: 10)
        let options = try XCTUnwrap(AxisStopFillPlanner.options(for: axis))
        XCTAssertTrue(options.recommendedCounts.allSatisfy { options.countRange.contains($0) })
    }
}
