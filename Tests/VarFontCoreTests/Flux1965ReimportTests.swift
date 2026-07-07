import XCTest
@testable import VarFontCore

/// Regression for vfcommit-written STAT v1.2 re-import (Flux1965 user report).
final class Flux1965ReimportTests: XCTestCase {
    private let outputPath =
        NSHomeDirectory() + "/Downloads/_Fonts/TTF/Flux 1965 Variable/Flux1965-Variable.ttf"

    func testPatchedFlux1965ReimportsAllWeightStops() throws {
        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw XCTSkip("Flux1965 patched output not at \(outputPath)")
        }

        let analysis = try FontAnalysisReader.analyze(url: URL(fileURLWithPath: outputPath))
        XCTAssertEqual(analysis.instancesExistingMeta?.total, 5)
        XCTAssertEqual(analysis.inferred.gridAxisTags, ["wght"])

        let wght = try XCTUnwrap(analysis.axes.first { $0.tag == "wght" })
        XCTAssertEqual(wght.roleInferred, .instance)
        XCTAssertEqual(wght.valuesExisting.count, 5)
        XCTAssertEqual(
            wght.valuesExisting.compactMap(\.value).sorted(),
            [30.0, 73.0, 115.0, 158.0, 200.0]
        )

        let project = try ProjectImporter.openFont(at: URL(fileURLWithPath: outputPath))
        let font = try XCTUnwrap(project.fonts.first)
        let wghtAxis = try XCTUnwrap(font.axes.first { $0.tag == "wght" })
        XCTAssertEqual(wghtAxis.role, .instance)
        XCTAssertEqual(wghtAxis.values.count, 5)

        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: font.id))
        XCTAssertEqual(plan.formula.parts, [5])
        XCTAssertEqual(plan.formula.totalGenerated, 5)
    }
}
