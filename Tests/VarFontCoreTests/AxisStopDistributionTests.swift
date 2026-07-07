import XCTest
@testable import VarFontCore

final class AxisStopDistributionTests: XCTestCase {
    private func weightAxis(min: Double, max: Double) -> AxisDefinition {
        AxisDefinition(tag: "wght", min: min, default: min, max: max, role: .instance, values: [])
    }

    func testEvenlySpacedFiveStops() throws {
        let axis = weightAxis(min: 0, max: 200)
        let values = try XCTUnwrap(AxisStopSuggestions.evenlySpacedValues(for: axis, count: 5))
        XCTAssertEqual(values, [0, 50, 100, 150, 200])
    }

    func testSteppedValuesEveryHundred() throws {
        let axis = weightAxis(min: 0, max: 200)
        let values = try XCTUnwrap(AxisStopSuggestions.steppedValues(for: axis, step: 100))
        XCTAssertEqual(values, [0, 100, 200])
    }

    func testSuggestedIntervalStep() {
        let axis = weightAxis(min: 0, max: 200)
        XCTAssertEqual(AxisStopSuggestions.suggestedIntervalStep(for: axis), 100)
    }
}
