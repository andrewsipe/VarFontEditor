import XCTest
@testable import VarFontCore

final class LiveFontImportPlanTests: XCTestCase {
    func testPlayfairRomanLiveImportProducesInstances() throws {
        guard let path = LiveFontFixture.playfairRomanPath else {
            throw XCTSkip("Playfair not found — see fixtures/fonts/README.md")
        }
        let project = try ProjectImporter.openFont(at: URL(fileURLWithPath: path))
        let font = try XCTUnwrap(project.fonts.first)
        dumpAxisGrid(font)
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: font.id))
        XCTAssertGreaterThan(plan.formula.totalGenerated, 0, "Expected instance grid; empty instance axes: \(emptyInstanceAxes(font))")
        XCTAssertEqual(plan.formula.totalGenerated, 252)
        XCTAssertEqual(plan.formula.parts, [12, 3, 7])
    }

    func testRobotoFlexLiveImportProducesInstances() throws {
        guard let path = LiveFontFixture.robotoFlexPath else {
            throw XCTSkip("Roboto Flex not found — see fixtures/fonts/README.md")
        }
        let project = try ProjectImporter.openFont(at: URL(fileURLWithPath: path))
        let font = try XCTUnwrap(project.fonts.first)
        dumpAxisGrid(font)
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: font.id))
        XCTAssertGreaterThan(plan.formula.totalGenerated, 0, "Expected instance grid; empty instance axes: \(emptyInstanceAxes(font))")
        XCTAssertEqual(plan.formula.parts, [9, 1])
        XCTAssertEqual(plan.formula.totalGenerated, 9)
    }

    private func dumpAxisGrid(_ font: FontDocument) {
        let grid = font.axes.filter { $0.role == .instance }
        print("grid axes:", grid.map { "\($0.tag)(\($0.values.count))" }.joined(separator: ", "))
    }

    private func emptyInstanceAxes(_ font: FontDocument) -> [String] {
        font.axes.filter { $0.role == .instance && $0.values.isEmpty }.map(\.tag)
    }
}
