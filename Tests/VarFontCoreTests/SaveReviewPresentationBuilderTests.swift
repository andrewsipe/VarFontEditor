import XCTest
@testable import VarFontCore

final class SaveReviewPresentationBuilderTests: XCTestCase {
    func testFvarAxesAreProtected() {
        let analysis = makeAnalysis()
        let font = makeFont()
        let plan = makePlan()
        let report = CommitDiffReport(
            statRows: [],
            instanceRows: [],
            nameIDRows: []
        )
        let presentation = SaveReviewPresentationBuilder.build(
            analysis: analysis,
            font: font,
            plan: plan,
            report: report,
            diff: nil
        )
        let fvar = presentation.tabs.first { $0.id == .fvar }
        XCTAssertNotNil(fvar)
        let axisRows = fvar?.sections.first { $0.title == "Axes" }?.rows ?? []
        XCTAssertEqual(axisRows.count, 1)
        XCTAssertTrue(axisRows.allSatisfy { $0.category == .protected })
        XCTAssertEqual(axisRows.first?.afterValue, "400 / 400 / 700")
    }

    func testFvarAxisRowNoteAppearsOnce() {
        let analysis = makeAnalysis()
        var font = makeFont()
        font.axes[0].default = 500
        let presentation = SaveReviewPresentationBuilder.build(
            analysis: analysis,
            font: font,
            plan: makePlan(),
            report: CommitDiffReport(statRows: [], instanceRows: [], nameIDRows: []),
            diff: nil
        )
        let axisRow = presentation.tabs.first { $0.id == .fvar }?
            .sections.first { $0.title == "Axes" }?.rows.first
        XCTAssertNotNil(axisRow?.noteLine)
        XCTAssertEqual(axisRow?.noteLine?.components(separatedBy: SaveReviewRowFormatter.fvarProtectedNote).count, 2)
    }

    func testNameReflowCategory() {
        let analysis = makeAnalysis()
        let font = makeFont()
        let plan = makePlan()
        let report = CommitDiffReport(
            statRows: [],
            instanceRows: [],
            nameIDRows: [
                CommitDiffNameIDRow(
                    id: 281,
                    beforeString: nil,
                    afterString: "Bold",
                    afterRole: "stat_axis_value",
                    change: .added,
                    reflowedFromNameID: 269
                ),
            ]
        )
        let presentation = SaveReviewPresentationBuilder.build(
            analysis: analysis,
            font: font,
            plan: plan,
            report: report,
            diff: CommitDiff(
                nameRecordsSequenced: [
                    .init(id: 279, string: "Weight", role: "axis_display_name"),
                    .init(id: 281, string: "Bold", role: "stat_axis_value"),
                ],
                statValuesPlanned: [
                    .init(tag: "wght", value: 700, name: "Bold", elidable: false, statFormat: 1, nameID: 281),
                ]
            )
        )
        let nameTab = presentation.tabs.first { $0.id == .name }
        let reflowRow = nameTab?.sections.flatMap(\.rows).first { $0.id == "name:281" }
        XCTAssertEqual(reflowRow?.category, .reflow)
        XCTAssertEqual(reflowRow?.wasLine, "slot moved from nameID 269")
    }

    func testRemovedSlotsSection() {
        let analysis = makeAnalysis()
        let font = makeFont()
        let plan = makePlan()
        let report = CommitDiffReport(
            statRows: [],
            instanceRows: [],
            nameIDRows: [
                CommitDiffNameIDRow(id: 290, beforeString: "Stale", afterString: nil, change: .removed),
            ]
        )
        let presentation = SaveReviewPresentationBuilder.build(
            analysis: analysis,
            font: font,
            plan: plan,
            report: report,
            diff: nil
        )
        let nameTab = presentation.tabs.first { $0.id == .name }
        let removed = nameTab?.sections.first { $0.title == "Removed slots" }
        XCTAssertEqual(removed?.rows.count, 1)
        XCTAssertEqual(removed?.rows.first?.category, .removed)
    }

    func testNameAxisDisplayRowsIncludeAxisTag() {
        let analysis = makeAnalysis()
        let font = makeFont()
        let report = CommitDiffReport(
            statRows: [],
            instanceRows: [],
            nameIDRows: [
                CommitDiffNameIDRow(
                    id: 279,
                    beforeString: "Weight",
                    afterString: "Weight",
                    afterRole: "axis_display_name",
                    change: .unchanged
                ),
            ]
        )
        let presentation = SaveReviewPresentationBuilder.build(
            analysis: analysis,
            font: font,
            plan: makePlan(),
            report: report,
            diff: CommitDiff(
                nameRecordsSequenced: [
                    .init(id: 279, string: "Weight", role: "axis_display_name"),
                ]
            )
        )
        let axisRow = presentation.tabs.first { $0.id == .name }?
            .sections.first { $0.title == "Axis records" }?.rows.first
        XCTAssertEqual(axisRow?.fieldTitle, "Weight (wght) axis")
    }

    // MARK: - Fixtures

    private func makeAnalysis() -> FontAnalysis {
        FontAnalysis(
            schemaVersion: 1,
            source: .init(path: "/t.ttf", format: "ttf", familyName: "Test", fullName: "Test", isVariable: true),
            readiness: .init(hasFvar: true, hasStat: true, hasDesignAxisRecord: true, writable: true, blockers: []),
            axes: [
                .init(
                    tag: "wght",
                    displayName: "Weight",
                    min: 400,
                    default: 400,
                    max: 700,
                    roleInferred: .instance,
                    variesInExistingInstances: true,
                    valuesExisting: []
                ),
            ],
            statValues: [],
            instancesExisting: [],
            instancesExistingMeta: .init(total: 0, sampleCount: 0),
            nameAudit: .init(freeStart: 256, used: [], elidedFallbackID: nil, elidedFallbackName: nil),
            inferred: .init(isItalicFont: false, gridAxisTags: ["wght"], namingOrderSuggested: ["wght"]),
            designAxisTags: ["wght"]
        )
    }

    private func makeFont() -> FontDocument {
        FontDocument(
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
                        AxisValue(id: "v1", value: 400, name: "Regular", elidable: true, statFormat: 1),
                        AxisValue(id: "v2", value: 700, name: "Bold", elidable: false, statFormat: 1),
                    ]
                ),
            ],
            options: CommitOptions(),
            includedInstanceKeys: [],
            excludedInstanceKeys: [],
            overrides: InstanceOverrides(),
            statDesignAxisTags: ["wght"]
        )
    }

    private func makePlan() -> InstancePlan {
        InstancePlan(
            schemaVersion: 1,
            fontID: "f1",
            formula: .init(parts: [], totalGenerated: 0, totalIncluded: 0, totalExcluded: 0),
            instances: [],
            warnings: [],
            namePlanSummary: nil
        )
    }
}
