import XCTest
@testable import VarFontCore

final class CommitDiffBuilderTests: XCTestCase {
    func testStatSameNameDifferentNameIDIsUnchanged() {
        let analysis = FontAnalysis(
            schemaVersion: 1,
            source: .init(path: "/t.ttf", format: "ttf", familyName: "Test", fullName: "Test", isVariable: true),
            readiness: .init(hasFvar: true, hasStat: true, hasDesignAxisRecord: true, writable: true, blockers: []),
            axes: [],
            statValues: [
                .init(
                    format: 1,
                    tag: "wght",
                    name: "Regular",
                    elidable: false,
                    olderSibling: false,
                    nameID: 269,
                    value: 750
                ),
            ],
            instancesExisting: [],
            instancesExistingMeta: .init(total: 0, sampleCount: 0),
            nameAudit: .init(freeStart: 256, used: [], elidedFallbackID: 261, elidedFallbackName: "Regular"),
            inferred: .init(isItalicFont: false, gridAxisTags: ["wght"], namingOrderSuggested: ["wght"]),
            designAxisTags: ["wght"]
        )

        let font = FontDocument(
            id: "f1",
            sourcePath: "/t.ttf",
            outputPath: nil,
            analysisSnapshotID: nil,
            dirty: false,
            axes: [
                AxisDefinition(
                    tag: "wght",
                    displayName: "Weight",
                    min: 0,
                    default: 400,
                    max: 1000,
                    role: .instance,
                    roleInferred: .instance,
                    values: [
                        AxisValue(
                            id: "w750",
                            value: 750,
                            name: "Regular",
                            elidable: false,
                            olderSibling: false,
                            statFormat: 1
                        ),
                    ]
                ),
            ]
        )

        let diff = CommitDiff(
            statValuesPlanned: [
                .init(
                    tag: "wght",
                    value: 750,
                    name: "Regular",
                    elidable: false,
                    statFormat: 1,
                    nameID: 261
                ),
            ]
        )

        let plan = InstancePlan(
            schemaVersion: 1,
            fontID: "f1",
            formula: PlanFormula(parts: [1], totalGenerated: 0, totalIncluded: 0, totalExcluded: 0),
            instances: [],
            warnings: [],
            namePlanSummary: nil
        )

        let result = CommitResult(
            schemaVersion: 1,
            requestID: "r1",
            ok: true,
            outputPath: nil,
            dryRun: true,
            summary: nil,
            diff: diff,
            warnings: [],
            errors: []
        )

        let report = CommitDiffBuilder.build(
            analysis: analysis,
            font: font,
            plan: plan,
            result: result
        )

        let row = report.statRows.first { $0.tag == "wght" && $0.value == 750 }
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.change, CommitDiffChangeKind.unchanged)
        if let row {
            XCTAssertEqual(SaveReviewDisplayCategoryMapper.category(for: row), .same)
        }
    }
}
