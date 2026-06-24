import XCTest
@testable import VarFontCore

final class InstancePlannerTests: XCTestCase {
    private let romanFontID = "11111111-1111-1111-1111-111111111101"

    func testPlanPlayfairRomanGrid() throws {
        let project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: romanFontID))

        XCTAssertEqual(plan.formula.parts, [3, 3, 3])
        XCTAssertEqual(plan.formula.totalGenerated, 27)
        XCTAssertEqual(plan.formula.totalIncluded, 27)
        XCTAssertEqual(plan.instances.count, 27)
        XCTAssertTrue(plan.warnings.isEmpty)
    }

    func testPlanMatchesFixtureSamples() throws {
        let project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        let sample = try FixtureLoader.decode(InstancePlan.self, from: "playfair-roman-instance-plan.json")
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: romanFontID))

        for expected in sample.instances {
            let actual = try XCTUnwrap(plan.instances.first { $0.key == expected.key })
            XCTAssertEqual(actual.composedName, expected.composedName)
            XCTAssertEqual(actual.coords, expected.coords)
            XCTAssertEqual(actual.namingChain, expected.namingChain)
        }
    }

    func testExclusionsReduceIncludedCount() throws {
        var project = try FixtureLoader.decode(ProjectDocument.self, from: "playfair-family-project.json")
        project.fonts[0].excludedInstanceKeys = [
            "ital:0|opsz:5|wdth:88|wght:360",
            "ital:0|opsz:5|wdth:100|wght:400",
        ]

        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: romanFontID))
        XCTAssertEqual(plan.formula.totalGenerated, 27)
        XCTAssertEqual(plan.formula.totalIncluded, 25)
        XCTAssertEqual(plan.formula.totalExcluded, 2)
    }

    func testMultipleElidableProducesWarning() {
        let font = FontDocument(
            id: "test",
            sourcePath: "/tmp/test.ttf",
            outputPath: nil,
            analysisSnapshotID: nil,
            dirty: false,
            axes: [
                AxisDefinition(
                    tag: "wght",
                    role: .instance,
                    values: [
                        AxisValue(id: "a", value: 400, name: "Regular", elidable: true),
                        AxisValue(id: "b", value: 500, name: "Medium", elidable: true),
                    ]
                ),
            ],
            options: CommitOptions(),
            includedInstanceKeys: [],
            excludedInstanceKeys: [],
            overrides: InstanceOverrides()
        )

        let plan = InstancePlanner.plan(
            font: font,
            naming: NamingPolicy(order: ["wght"], elidedFallback: "Regular")
        )
        XCTAssertTrue(plan.warnings.contains { $0.code == "multiple_elidable" })
    }

    func testConflictingInstanceKeysProduceWarning() {
        let font = FontDocument(
            id: "test",
            sourcePath: "/tmp/test.ttf",
            outputPath: nil,
            analysisSnapshotID: nil,
            dirty: false,
            axes: [
                AxisDefinition(
                    tag: "wght",
                    role: .instance,
                    values: [AxisValue(id: "a", value: 400, name: "Regular", elidable: false)]
                ),
            ],
            options: CommitOptions(),
            includedInstanceKeys: ["wght:400"],
            excludedInstanceKeys: ["wght:400"],
            overrides: InstanceOverrides()
        )

        let plan = InstancePlanner.plan(
            font: font,
            naming: NamingPolicy(order: ["wght"], elidedFallback: "Regular")
        )
        XCTAssertTrue(plan.warnings.contains { $0.code == "conflicting_instance_keys" })
    }

    func testCommitServiceDryRun() async throws {
        let request = try FixtureLoader.decode(CommitRequest.self, from: "playfair-roman-commit-request.json")
        let service = CommitService()
        let result = try await service.commit(request)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.dryRun)
        XCTAssertEqual(result.summary?.instancesWritten, request.includedInstanceKeys.count)
    }

    func testCommitServiceNonDryRunNotImplemented() async throws {
        var request = try FixtureLoader.decode(CommitRequest.self, from: "playfair-roman-commit-request.json")
        request.dryRun = false
        let service = CommitService()

        do {
            _ = try await service.commit(request)
            XCTFail("Expected notImplemented")
        } catch CommitServiceError.notImplemented {
            // expected
        }
    }
}
