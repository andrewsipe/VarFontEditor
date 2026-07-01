import XCTest
@testable import VarFontCore

final class DesignRecordAxisTests: XCTestCase {
    func testImportPlayfairRomanIncludesDesignRecordItalAxis() throws {
        let analysis = try FixtureLoader.decode(FontAnalysis.self, from: "playfair-roman-analysis.json")
        let ital = analysis.axes.first { $0.tag == "ital" }
        XCTAssertNotNil(ital)
        XCTAssertEqual(ital?.roleInferred, .designRecordOnly)
        XCTAssertEqual(ital?.displayName, "Italic")
        XCTAssertEqual(ital?.valuesExisting.count, 1)
        XCTAssertEqual(ital?.valuesExisting.first?.name, "Roman")

        let project = ProjectImporter.newProject(
            from: analysis,
            sourceURL: URL(fileURLWithPath: analysis.source.path)
        )
        let font = project.fonts[0]
        let axis = font.axes.first { $0.tag == "ital" }
        XCTAssertNotNil(axis)
        XCTAssertEqual(axis?.role, .designRecordOnly)
        XCTAssertNil(axis?.min)
        XCTAssertNil(axis?.default)
        XCTAssertNil(axis?.max)
        XCTAssertEqual(axis?.values.first?.statFormat, 3)
        XCTAssertEqual(axis?.values.first?.linkedValue, 1.0)
    }

    func testDesignRecordAxisExcludedFromInstanceGridAndPinnedCoords() throws {
        let analysis = try FixtureLoader.decode(FontAnalysis.self, from: "playfair-roman-analysis.json")
        let project = ProjectImporter.newProject(
            from: analysis,
            sourceURL: URL(fileURLWithPath: analysis.source.path)
        )
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: project.fonts[0].id))

        XCTAssertEqual(plan.formula.parts, [3, 3, 3])
        XCTAssertFalse(plan.instances.contains { $0.coords.keys.contains("ital") })
    }

    func testDesignRecordAxisRoleDecodesFromJSON() throws {
        let json = """
        {"tag":"ital","display_name":"Italic","role":"design_record_only","values":[]}
        """
        let axis = try VarFontJSON.decoder.decode(AxisDefinition.self, from: Data(json.utf8))
        XCTAssertTrue(axis.isDesignRecordOnly)
        XCTAssertFalse(axis.hasFvarScale)
    }
}
