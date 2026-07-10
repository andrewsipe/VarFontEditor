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

    /// Regression: a 30–200 range previously produced an interval lower bound of
    /// 170 / 11 = 15.454545..., and every slider position downstream of it inherited
    /// that repeating decimal (e.g. 165.45454545454547). Bounds must land on "nice"
    /// numbers (1/2/5 × 10^n) so every reachable value is clean.
    func testIntervalRangeIsFreeOfRepeatingDecimals() throws {
        let axis = weightAxis(min: 30, max: 200)
        let options = try XCTUnwrap(AxisStopFillPlanner.options(for: axis))
        XCTAssertEqual((options.intervalRange.lowerBound * 100).rounded() / 100, options.intervalRange.lowerBound)
        XCTAssertEqual((options.intervalRange.upperBound * 100).rounded() / 100, options.intervalRange.upperBound)
        XCTAssertEqual((options.defaultInterval * 100).rounded() / 100, options.defaultInterval)
    }

    /// The smallest selectable interval must never produce more than maxStopCount stops,
    /// regardless of how the range divides.
    func testIntervalLowerBoundNeverExceedsStopCap() throws {
        for max in stride(from: 20.0, through: 500, by: 17) {
            let axis = weightAxis(min: 0, max: max)
            guard let options = AxisStopFillPlanner.options(for: axis) else { continue }
            let values = try XCTUnwrap(AxisStopFillPlanner.values(for: axis, interval: options.intervalRange.lowerBound))
            XCTAssertLessThanOrEqual(values.count, AxisStopFillPlanner.maxStopCount)
        }
    }

    /// Boolean-style axes like `ital` (0–1) shouldn't offer quick fill — subdividing a
    /// span that narrow into evenly spaced "stops" isn't a meaningful design choice.
    func testBooleanStyleAxisDoesNotSupportFill() {
        let axis = AxisDefinition(tag: "ital", min: 0, default: 0, max: 1, role: .instance, values: [])
        XCTAssertFalse(AxisStopFillPlanner.supportsFill(axis))
        XCTAssertNil(AxisStopFillPlanner.options(for: axis))
    }

    /// Quick fill should remain available on axes that already have stops — the
    /// standalone tool replaces them (see EditorViewModel.replaceAxisStops), rather than
    /// require the axis to be empty like the plan-issue resolver's insertAxisStops fix.
    func testFillSupportedRegardlessOfExistingStops() {
        var axis = weightAxis(min: 0, max: 200)
        axis.values = [AxisValue(id: "1", value: 100, name: "Regular", elidable: true)]
        XCTAssertTrue(AxisStopFillPlanner.supportsFill(axis))
        XCTAssertNotNil(AxisStopFillPlanner.options(for: axis))
    }
}
