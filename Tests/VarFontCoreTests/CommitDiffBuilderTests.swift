import XCTest
@testable import VarFontCore

final class CommitDiffBuilderTests: XCTestCase {
    func testStatRowsDetectRegularToNamedChange() {
        let analysis = FontAnalysis(
            schemaVersion: 1,
            source: .init(path: "/t.ttf", format: "ttf", familyName: "Test", fullName: "Test", isVariable: true),
            readiness: .init(hasFvar: true, hasStat: true, hasDesignAxisRecord: true, writable: true, blockers: []),
            axes: [],
            statValues: [
                .init(format: 1, tag: "wght", name: "Regular", elidable: true, nameID: 2, value: 400),
            ],
            instancesExisting: [],
            instancesExistingMeta: .init(total: 0, sampleCount: 0),
            nameAudit: .init(freeStart: 256, used: [], elidedFallbackID: 2, elidedFallbackName: "Regular"),
            inferred: .init(isItalicFont: false, gridAxisTags: ["wght"], namingOrderSuggested: ["wght"])
        )

        let font = FontDocument(
            id: "f1",
            sourcePath: "/t.ttf",
            outputPath: nil,
            analysisSnapshotID: nil,
            dirty: true,
            axes: [
                AxisDefinition(
                    tag: "wght",
                    displayName: "Weight",
                    min: 400,
                    default: 400,
                    max: 700,
                    role: .instance,
                    values: [
                        AxisValue(id: "w1", value: 400, name: "Normal", elidable: true, statFormat: 1),
                    ]
                ),
            ],
            options: CommitOptions(),
            includedInstanceKeys: [],
            excludedInstanceKeys: [],
            overrides: InstanceOverrides()
        )

        let plan = InstancePlan(
            schemaVersion: 1,
            fontID: "f1",
            formula: .init(parts: [1], totalGenerated: 1, totalIncluded: 1, totalExcluded: 0),
            instances: [],
            warnings: [],
            namePlanSummary: nil
        )

        let result = CommitResult(
            schemaVersion: 1,
            requestID: "x",
            ok: true,
            outputPath: nil,
            dryRun: true,
            summary: nil,
            diff: CommitDiff(
                statValuesPlanned: [
                    .init(tag: "wght", value: 400, name: "Normal", elidable: true, statFormat: 1, nameID: 280),
                ]
            ),
            warnings: [],
            errors: []
        )

        let report = CommitDiffBuilder.build(analysis: analysis, font: font, plan: plan, result: result)
        XCTAssertEqual(report.statRows.count, 1)
        XCTAssertEqual(report.statRows[0].change, .changed)
        XCTAssertEqual(report.statRows[0].beforeName, "Regular")
        XCTAssertEqual(report.statRows[0].afterName, "Normal")
        XCTAssertEqual(report.statRows[0].afterNameID, 280)
    }

    func testInstanceRowsAddedRemoved() {
        let analysis = FontAnalysis(
            schemaVersion: 1,
            source: .init(path: "/t.ttf", format: "ttf", familyName: "Test", fullName: "Test", isVariable: true),
            readiness: .init(hasFvar: true, hasStat: true, hasDesignAxisRecord: true, writable: true, blockers: []),
            axes: [],
            statValues: [],
            instancesExisting: [
                .init(
                    key: "wght:400",
                    composedName: "Regular",
                    coords: ["wght": 400],
                    subfamilyNameID: 2,
                    postscriptNameID: 0xFFFF
                ),
            ],
            instancesExistingMeta: .init(total: 1, sampleCount: 1),
            nameAudit: .init(freeStart: 256, used: [], elidedFallbackID: nil, elidedFallbackName: nil),
            inferred: .init(isItalicFont: false, gridAxisTags: [], namingOrderSuggested: [])
        )

        let font = FontDocument(
            id: "f1",
            sourcePath: "/t.ttf",
            outputPath: nil,
            analysisSnapshotID: nil,
            dirty: true,
            axes: [],
            options: CommitOptions(),
            includedInstanceKeys: [],
            excludedInstanceKeys: [],
            overrides: InstanceOverrides()
        )

        let plan = InstancePlan(
            schemaVersion: 1,
            fontID: "f1",
            formula: .init(parts: [1], totalGenerated: 1, totalIncluded: 1, totalExcluded: 0),
            instances: [
                PlannedInstance(
                    key: "wght:700",
                    composedName: "Bold",
                    coords: ["wght": 700],
                    included: true,
                    duplicate: false,
                    namingChain: []
                ),
            ],
            warnings: [],
            namePlanSummary: nil
        )

        let result = CommitResult(
            schemaVersion: 1,
            requestID: "x",
            ok: true,
            outputPath: nil,
            dryRun: true,
            summary: nil,
            diff: nil,
            warnings: [],
            errors: []
        )

        let report = CommitDiffBuilder.build(analysis: analysis, font: font, plan: plan, result: result)
        XCTAssertEqual(report.instanceRows.count, 2)
        XCTAssertEqual(report.instanceRows.first { $0.key == "wght:400" }?.change, .removed)
        XCTAssertEqual(report.instanceRows.first { $0.key == "wght:700" }?.change, .added)
    }

    func testNameIDRowsUseSequencedSlots() {
        let analysis = FontAnalysis(
            schemaVersion: 1,
            source: .init(path: "/t.ttf", format: "ttf", familyName: "Test", fullName: "Test", isVariable: true),
            readiness: .init(hasFvar: true, hasStat: true, hasDesignAxisRecord: true, writable: true, blockers: []),
            axes: [],
            statValues: [],
            instancesExisting: [],
            instancesExistingMeta: .init(total: 0, sampleCount: 0),
            nameAudit: .init(
                freeStart: 256,
                used: [
                    .init(id: 256, description: "fvar axis wght", string: "Weight"),
                    .init(id: 258, description: "STAT wght", string: "Medium"),
                ],
                elidedFallbackID: nil,
                elidedFallbackName: nil
            ),
            inferred: .init(isItalicFont: false, gridAxisTags: [], namingOrderSuggested: [])
        )

        let result = CommitResult(
            schemaVersion: 1,
            requestID: "x",
            ok: true,
            outputPath: nil,
            dryRun: true,
            summary: nil,
            diff: CommitDiff(
                nameRecordsPlanned: [
                    .init(id: 256, string: "Weight", role: "axis_display_name"),
                    .init(id: 257, string: "Medium", role: "stat_axis_value"),
                ]
            ),
            warnings: [],
            errors: []
        )

        let report = CommitDiffBuilder.build(
            analysis: analysis,
            font: FontDocument(
                id: "f1", sourcePath: "/t.ttf", outputPath: nil, analysisSnapshotID: nil,
                dirty: true, axes: [], options: CommitOptions(),
                includedInstanceKeys: [], excludedInstanceKeys: [], overrides: InstanceOverrides()
            ),
            plan: InstancePlan(
                schemaVersion: 1, fontID: "f1",
                formula: .init(parts: [], totalGenerated: 0, totalIncluded: 0, totalExcluded: 0),
                instances: [], warnings: [], namePlanSummary: nil
            ),
            result: result
        )

        XCTAssertEqual(report.nameIDRows.count, 3)
        XCTAssertEqual(report.nameIDRows.first { $0.id == 256 }?.change, .unchanged)
        XCTAssertEqual(report.nameIDRows.first { $0.id == 257 }?.change, .added)
        XCTAssertEqual(report.nameIDRows.first { $0.id == 258 }?.change, .removed)
    }

    func testInstanceRowsFollowPlanOrder() {
        let analysis = FontAnalysis(
            schemaVersion: 1,
            source: .init(path: "/t.ttf", format: "ttf", familyName: "Test", fullName: "Test", isVariable: true),
            readiness: .init(hasFvar: true, hasStat: true, hasDesignAxisRecord: true, writable: true, blockers: []),
            axes: [],
            statValues: [],
            instancesExisting: [
                .init(key: "wght:400", composedName: "Regular", coords: ["wght": 400], subfamilyNameID: 2, postscriptNameID: 0xFFFF),
                .init(key: "wght:300", composedName: "Light", coords: ["wght": 300], subfamilyNameID: 2, postscriptNameID: 0xFFFF),
            ],
            instancesExistingMeta: .init(total: 2, sampleCount: 2),
            nameAudit: .init(freeStart: 256, used: [], elidedFallbackID: nil, elidedFallbackName: nil),
            inferred: .init(isItalicFont: false, gridAxisTags: [], namingOrderSuggested: ["wght"])
        )

        let font = FontDocument(
            id: "f1", sourcePath: "/t.ttf", outputPath: nil, analysisSnapshotID: nil,
            dirty: true, axes: [], options: CommitOptions(),
            includedInstanceKeys: [], excludedInstanceKeys: [], overrides: InstanceOverrides()
        )

        let plan = InstancePlan(
            schemaVersion: 1, fontID: "f1",
            formula: .init(parts: [], totalGenerated: 2, totalIncluded: 2, totalExcluded: 0),
            instances: [
                PlannedInstance(key: "wght:700", composedName: "Bold", coords: ["wght": 700], included: true, duplicate: false, namingChain: []),
                PlannedInstance(key: "wght:400", composedName: "Regular", coords: ["wght": 400], included: true, duplicate: false, namingChain: []),
            ],
            warnings: [], namePlanSummary: nil
        )

        let result = CommitResult(
            schemaVersion: 1, requestID: "x", ok: true, outputPath: nil, dryRun: true,
            summary: nil, diff: nil, warnings: [], errors: []
        )

        let report = CommitDiffBuilder.build(analysis: analysis, font: font, plan: plan, result: result)
        XCTAssertEqual(report.instanceRows.map(\.key), ["wght:700", "wght:400", "wght:300"])
    }

    func testNameIDReflowDetection() {
        let analysis = FontAnalysis(
            schemaVersion: 1,
            source: .init(path: "/t.ttf", format: "ttf", familyName: "Test", fullName: "Test", isVariable: true),
            readiness: .init(hasFvar: true, hasStat: true, hasDesignAxisRecord: true, writable: true, blockers: []),
            axes: [],
            statValues: [],
            instancesExisting: [],
            instancesExistingMeta: .init(total: 0, sampleCount: 0),
            nameAudit: .init(
                freeStart: 256,
                used: [.init(id: 258, description: "STAT", string: "Medium")],
                elidedFallbackID: nil, elidedFallbackName: nil
            ),
            inferred: .init(isItalicFont: false, gridAxisTags: [], namingOrderSuggested: [])
        )

        let result = CommitResult(
            schemaVersion: 1, requestID: "x", ok: true, outputPath: nil, dryRun: true,
            summary: nil,
            diff: CommitDiff(
                nameRecordsPlanned: [.init(id: 257, string: "Medium", role: "stat_axis_value")]
            ),
            warnings: [], errors: []
        )

        let report = CommitDiffBuilder.build(
            analysis: analysis,
            font: FontDocument(
                id: "f1", sourcePath: "/t.ttf", outputPath: nil, analysisSnapshotID: nil,
                dirty: true, axes: [], options: CommitOptions(),
                includedInstanceKeys: [], excludedInstanceKeys: [], overrides: InstanceOverrides()
            ),
            plan: InstancePlan(
                schemaVersion: 1, fontID: "f1",
                formula: .init(parts: [], totalGenerated: 0, totalIncluded: 0, totalExcluded: 0),
                instances: [], warnings: [], namePlanSummary: nil
            ),
            result: result
        )

        let added = report.nameIDRows.first { $0.id == 257 }
        let removed = report.nameIDRows.first { $0.id == 258 }
        XCTAssertEqual(added?.reflowedFromNameID, 258)
        XCTAssertTrue(removed?.reflowSuppressed == true)
    }
}
