import XCTest
@testable import VarFontCore

final class ProjectImporterTests: XCTestCase {
    func testImportPlayfairFamilyFixtureShape() throws {
        let analysis = try FixtureLoader.decode(FontAnalysis.self, from: "playfair-roman-analysis.json")
        let project = ProjectImporter.newProject(
            from: analysis,
            sourceURL: URL(fileURLWithPath: analysis.source.path)
        )

        XCTAssertEqual(project.schemaVersion, 1)
        XCTAssertEqual(project.fonts.count, 1)
        XCTAssertFalse(project.fonts[0].axes.isEmpty)
        XCTAssertTrue(project.naming.order.contains("wght"))

        let plan = InstancePlanner.plan(project: project, fontID: project.fonts[0].id)
        XCTAssertNotNil(plan)
        XCTAssertGreaterThan(plan?.formula.totalGenerated ?? 0, 0)
    }

    func testAddFontSyncsProjectNameIDStrategy() throws {
        var project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        project.nameidStrategy = .reflow
        project.syncNameIDStrategyToFonts()
        XCTAssertEqual(project.fonts.first?.options.nameidStrategy, .reflow)

        let analysis = try FixtureLoader.decode(FontAnalysis.self, from: "playfair-italic-analysis.json")
        let sourceURL = URL(fileURLWithPath: "/tmp/Playfair-VariableFont-Micro-SemiCond-Italic.woff2")

        ProjectImporter.addFont(analysis, sourceURL: sourceURL, to: &project)

        XCTAssertEqual(project.fonts.last?.options.nameidStrategy, .reflow)
    }
}
