import XCTest
@testable import VarFontCore

final class Format2StopTests: XCTestCase {
    func testImportPreservesFormat2RangeFields() throws {
        let analysis = try FixtureLoader.decode(FontAnalysis.self, from: "melange-format2-analysis.json")
        let project = ProjectImporter.newProject(
            from: analysis,
            sourceURL: URL(fileURLWithPath: analysis.source.path)
        )
        let opsz = project.fonts[0].axes.first { $0.tag == "opsz" }
        let stop = try XCTUnwrap(opsz?.values.first)
        XCTAssertEqual(stop.statFormat, 2)
        XCTAssertEqual(stop.value, 12)
        XCTAssertEqual(stop.rangeMin, 6)
        XCTAssertEqual(stop.rangeMax, 18)
    }

    func testCommitDiffStatKeyIncludesRange() throws {
        let analysis = try FixtureLoader.decode(FontAnalysis.self, from: "melange-format2-analysis.json")
        let project = ProjectImporter.newProject(
            from: analysis,
            sourceURL: URL(fileURLWithPath: analysis.source.path)
        )
        let font = project.fonts[0]
        let plan = InstancePlanner.plan(font: font, naming: project.naming)
        let request = CommitRequestBuilder.make(
            font: font,
            naming: project.naming,
            plan: plan,
            outputPath: "/tmp/out.ttf",
            dryRun: true
        )
        let opszStop = try XCTUnwrap(request.axes.first { $0.tag == "opsz" }?.values.first)
        XCTAssertEqual(opszStop.statFormat, 2)
        XCTAssertEqual(opszStop.rangeMin, 6)
        XCTAssertEqual(opszStop.rangeMax, 18)
    }
}
