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
            "opsz:5|wdth:88|wght:360",
            "opsz:5|wdth:100|wght:400",
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

    func testStatOnlyAxisExcludedFromComposedNameAndGrid() {
        let font = FontDocument(
            id: "test",
            sourcePath: "/tmp/test.ttf",
            outputPath: nil,
            analysisSnapshotID: nil,
            dirty: false,
            axes: [
                AxisDefinition(
                    tag: "opsz",
                    role: .instance,
                    values: [
                        AxisValue(id: "opsz-a", value: 5, name: "Micro", elidable: false),
                        AxisValue(id: "opsz-b", value: 6, name: "Minuscule", elidable: false),
                    ]
                ),
                AxisDefinition(
                    tag: "wdth",
                    min: 88,
                    default: 88,
                    role: .statOnly,
                    values: [
                        AxisValue(id: "wdth-a", value: 88, name: "SemiCondensed", elidable: false),
                        AxisValue(id: "wdth-b", value: 100, name: "Normal", elidable: true),
                    ]
                ),
                AxisDefinition(
                    tag: "wght",
                    role: .instance,
                    values: [
                        AxisValue(id: "wght-a", value: 400, name: "Regular", elidable: false),
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
            naming: NamingPolicy(order: ["opsz", "wdth", "wght"], elidedFallback: "Regular")
        )

        XCTAssertEqual(plan.formula.parts, [2, 1])
        XCTAssertEqual(plan.instances.count, 2)
        XCTAssertTrue(plan.instances.allSatisfy { !$0.composedName.contains("SemiCondensed") })
        XCTAssertEqual(plan.instances[0].composedName, "Micro Regular")
        XCTAssertEqual(plan.instances[0].coords["wdth"], 88)
        XCTAssertEqual(plan.instances[0].namingChain.map(\NamingChainLink.tag), ["opsz", "wght"])
    }

    func testCommitServiceDryRun() async throws {
        let request = try FixtureLoader.decode(CommitRequest.self, from: "playfair-roman-commit-request.json")
        let service = CommitService()
        let result = try await service.commit(request)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.dryRun)
        XCTAssertEqual(result.summary?.instancesWritten, request.includedInstanceKeys.count)
    }
}
