import XCTest
@testable import VarFontCore

final class SchemaDecodeTests: XCTestCase {
    func testDecodeRobotoFlexAnalysis() throws {
        let analysis = try FixtureLoader.decode(FontAnalysis.self, from: "roboto-flex-analysis.json")
        XCTAssertEqual(analysis.schemaVersion, 1)
        XCTAssertTrue(analysis.readiness.hasFvar)
        XCTAssertEqual(analysis.instancesExistingMeta?.total, 20)
        XCTAssertEqual(analysis.inferred.gridAxisTags, ["slnt", "wght"])
        XCTAssertEqual(analysis.axes.count, 13)
    }

    func testDecodePlayfairRomanAnalysis() throws {
        let analysis = try FixtureLoader.decode(FontAnalysis.self, from: "playfair-roman-analysis.json")
        XCTAssertEqual(analysis.instancesExistingMeta?.total, 252)
        XCTAssertTrue(analysis.inferred.gridAxisTags.contains("wght"))
    }

    func testDecodePlayfairFamilyProject() throws {
        let project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        XCTAssertEqual(project.schemaVersion, 1)
        XCTAssertEqual(project.fonts.count, 2)
        XCTAssertEqual(project.naming.order, ["opsz", "wdth", "wght", "ital"])
        XCTAssertEqual(project.template.axes.count, 3)
    }

    func testDecodePlayfairInstancePlanSample() throws {
        let plan = try FixtureLoader.decode(InstancePlan.self, from: "playfair-roman-instance-plan.json")
        XCTAssertEqual(plan.formula.parts, [3, 3, 3])
        XCTAssertEqual(plan.formula.totalGenerated, 27)
        XCTAssertEqual(plan.instances.count, 3)
    }

    func testDecodeCommitRequestDryRun() throws {
        let request = try FixtureLoader.decode(CommitRequest.self, from: "playfair-roman-commit-request.json")
        XCTAssertTrue(request.dryRun)
        XCTAssertFalse(request.axes.isEmpty)
    }

    func testDecodeCommitResultSuccess() throws {
        let result = try FixtureLoader.decode(CommitResult.self, from: "commit-result-success.json")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.summary?.instancesWritten, 8)
        XCTAssertEqual(result.diff?.familyPSPrefix, "PlayfairVF")
        XCTAssertEqual(result.diff?.nameRecordsPlanned.first?.string, "Bold")
        XCTAssertEqual(result.diff?.statValuesPlanned.first?.name, "Normal")
    }

    func testRoundTripProjectEncoding() throws {
        let project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        let data = try VarFontJSON.encoder.encode(project)
        let roundTrip = try VarFontJSON.decode(ProjectDocument.self, from: data)
        XCTAssertEqual(roundTrip.familyLabel, project.familyLabel)
        XCTAssertEqual(roundTrip.fonts.map(\.id), project.fonts.map(\.id))
    }
}
