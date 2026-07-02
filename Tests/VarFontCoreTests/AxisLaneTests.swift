import XCTest
@testable import VarFontCore

final class AxisLaneTests: XCTestCase {
    func testLaneVariation() {
        let axis = AxisDefinition(tag: "wght", min: 100, role: .instance, values: [])
        XCTAssertEqual(axis.lane, .variation)
        XCTAssertNil(axis.pinCoordinate)
    }

    func testLanePinned() {
        let axis = AxisDefinition(
            tag: "GRAD",
            min: 0,
            default: 0,
            role: .statOnly,
            values: [AxisValue(id: "g", value: 0, name: "Default", elidable: false)]
        )
        XCTAssertEqual(axis.lane, .pinned)
        XCTAssertEqual(axis.pinCoordinate, 0)
    }

    func testLaneRegistration() {
        let axis = AxisDefinition(
            tag: "ital",
            role: .designRecordOnly,
            values: [AxisValue(id: "i", value: 0, name: "Roman", elidable: true, statFormat: 3, linkedValue: 1)]
        )
        XCTAssertEqual(axis.lane, .registration)
        XCTAssertFalse(axis.hasFvarScale)
        XCTAssertNil(axis.pinCoordinate)
    }

    func testHasFvarScaleRequiresMin() {
        let withMin = AxisDefinition(tag: "wdth", min: 88, role: .statOnly, values: [])
        let withoutMin = AxisDefinition(tag: "wdth", default: 88, role: .statOnly, values: [])
        XCTAssertTrue(withMin.hasFvarScale)
        XCTAssertFalse(withoutMin.hasFvarScale)
    }

    func testPinPolicyMatchesInstancePlanner() throws {
        let project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        let font = try XCTUnwrap(project.fonts.first)
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: font.id))
        XCTAssertFalse(plan.instances.contains { $0.coords.keys.contains("ital") })
    }
}
