import XCTest
@testable import VarFontCore

final class RegistrationNamingTests: XCTestCase {
    func testRomanFileDoesNotAddItalicSegment() throws {
        var project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        project.fonts[0].fileStatRegistration = ["ital": 0]
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: project.fonts[0].id))
        XCTAssertTrue(plan.instances.allSatisfy { !$0.composedName.localizedCaseInsensitiveContains("italic") })
    }

    func testImportSeedsFileStatRegistration() throws {
        let analysis = try FixtureLoader.decode(FontAnalysis.self, from: "playfair-roman-analysis.json")
        let project = ProjectImporter.newProject(
            from: analysis,
            sourceURL: URL(fileURLWithPath: analysis.source.path)
        )
        XCTAssertEqual(project.fonts[0].fileStatRegistration["ital"], 0)
    }

    func testSlopeClarifierSkippedWhenDesignRecordItalPresent() {
        let font = FontDocument(
            id: "test",
            sourcePath: "/tmp/PlayfairRomanVF.woff2",
            axes: [
                AxisDefinition(
                    tag: "ital",
                    role: .designRecordOnly,
                    values: [AxisValue(id: "i", value: 0, name: "Roman", elidable: true)]
                ),
            ],
            fileStatRegistration: ["ital": 0]
        )
        let result = FileClarifierInference.infer(
            sourceURL: URL(fileURLWithPath: font.sourcePath),
            analysis: nil,
            font: font
        )
        XCTAssertFalse(result.clarifiers.contains { $0.category == .slope })
    }
}
