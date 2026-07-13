import XCTest
@testable import VarFontCore

final class CommitRequestBuilderTests: XCTestCase {
    private let romanFontID = "11111111-1111-1111-1111-111111111101"

    func testBuildsFromProjectState() throws {
        let project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        let font = try XCTUnwrap(project.fonts.first { $0.id == romanFontID })
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: romanFontID))

        let request = CommitRequestBuilder.make(
            font: font,
            naming: project.naming,
            plan: plan,
            outputPath: "/tmp/PlayfairRomanVF-patched.woff2",
            dryRun: true
        )

        XCTAssertEqual(request.schemaVersion, 1)
        XCTAssertEqual(request.sourcePath, font.sourcePath)
        XCTAssertTrue(request.dryRun)
        XCTAssertEqual(request.axes.count, font.axes.count)
        XCTAssertEqual(request.axes.map(\.tag), CommitRequestBuilder.orderedAxes(font.axes, naming: project.naming).map(\.tag))
        XCTAssertTrue(request.includedInstanceKeys.isEmpty)
    }

    func testIncludedKeysWhenExcluded() throws {
        var project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        project.fonts[0].excludedInstanceKeys = [
            "opsz:5|wdth:88|wght:360",
        ]
        let font = project.fonts[0]
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: romanFontID))

        let keys = CommitRequestBuilder.includedInstanceKeys(font: font, plan: plan)
        XCTAssertEqual(keys.count, plan.formula.totalIncluded)
        XCTAssertFalse(keys.contains("opsz:5|wdth:88|wght:360"))
    }

    func testSuggestedOutputPathPreservesExtension() {
        let path = CommitRequestBuilder.suggestedOutputPath(
            for: "/Users/test/PlayfairRomanVF.woff2"
        )
        XCTAssertEqual(path, "/Users/test/PlayfairRomanVF-patched.woff2")
    }

    func testPackageOutputPathUsesOriginalBasename() {
        let directory = URL(fileURLWithPath: "/Users/test/ExportPackage")
        let path = CommitRequestBuilder.packageOutputPath(
            for: "/Users/test/fonts/PlayfairRomanVF.woff2",
            in: directory
        )
        XCTAssertEqual(path, "/Users/test/ExportPackage/PlayfairRomanVF.woff2")
    }

    func testCommitNamingPrunesPhantomTokens() {
        let order = NamingPolicy.mergedOrder(
            projectOrder: [
                "opsz", "wdth", "wght", "ital", "slnt",
                "@width", "@slope", "@optical", "@custom",
            ],
            axisTags: ["wght"]
        )

        XCTAssertEqual(order, ["@pshyphen", "wght", "@width", "@slope", "@optical", "@custom"])
        XCTAssertFalse(order.contains("slnt"))
        XCTAssertFalse(order.contains("ital"))
    }

    func testMakeAppliesProjectNameIDStrategyPreserve() throws {
        let project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        let font = try XCTUnwrap(project.fonts.first { $0.id == romanFontID })
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: romanFontID))

        let request = CommitRequestBuilder.make(
            font: font,
            naming: project.naming,
            plan: plan,
            outputPath: "/tmp/PlayfairRomanVF-patched.woff2",
            dryRun: true,
            nameidStrategy: .preserve
        )

        XCTAssertEqual(request.options.nameidStrategy, .preserve)
    }

    func testMakeAppliesProjectNameIDStrategyReflow() throws {
        let project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        let font = try XCTUnwrap(project.fonts.first { $0.id == romanFontID })
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: romanFontID))

        let request = CommitRequestBuilder.make(
            font: font,
            naming: project.naming,
            plan: plan,
            outputPath: "/tmp/PlayfairRomanVF-patched.woff2",
            dryRun: true,
            nameidStrategy: .reflow
        )

        XCTAssertEqual(request.options.nameidStrategy, .reflow)
    }
}
