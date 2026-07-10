import XCTest
@testable import VarFontCore

final class FvarDesignSpaceAuditTests: XCTestCase {
    func testNoNotesWhenProjectMatchesSource() {
        let analysis = FontAnalysis(
            schemaVersion: 1,
            source: .init(
                path: "/tmp/font.ttf",
                format: "ttf",
                familyName: "Test",
                fullName: "Test",
                isVariable: true
            ),
            readiness: .init(
                hasFvar: true,
                hasStat: true,
                hasDesignAxisRecord: true,
                writable: true,
                blockers: []
            ),
            axes: [
                .init(
                    tag: "wght",
                    displayName: "Weight",
                    min: 100,
                    default: 400,
                    max: 900,
                    roleInferred: .instance,
                    variesInExistingInstances: true,
                    valuesExisting: []
                ),
            ],
            statValues: [],
            compoundStatValues: [],
            instancesExisting: [],
            nameAudit: .init(freeStart: 256, used: []),
            inferred: .init(isItalicFont: false, gridAxisTags: ["wght"], namingOrderSuggested: ["wght"])
        )
        let font = FontDocument(
            id: "f1",
            sourcePath: "/tmp/font.ttf",
            axes: [
                AxisDefinition(
                    tag: "wght",
                    min: 100,
                    default: 400,
                    max: 900,
                    role: .instance,
                    values: []
                ),
            ]
        )

        XCTAssertTrue(FvarDesignSpaceAudit.informationalMessages(analysis: analysis, font: font).isEmpty)
    }

    func testNotesWhenProjectDefaultDriftsFromSource() {
        let analysis = FontAnalysis(
            schemaVersion: 1,
            source: .init(
                path: "/tmp/font.ttf",
                format: "ttf",
                familyName: "Test",
                fullName: "Test",
                isVariable: true
            ),
            readiness: .init(
                hasFvar: true,
                hasStat: true,
                hasDesignAxisRecord: true,
                writable: true,
                blockers: []
            ),
            axes: [
                .init(
                    tag: "opsz",
                    displayName: "Optical Size",
                    min: 5,
                    default: 5,
                    max: 1200,
                    roleInferred: .instance,
                    variesInExistingInstances: true,
                    valuesExisting: []
                ),
            ],
            statValues: [],
            compoundStatValues: [],
            instancesExisting: [],
            nameAudit: .init(freeStart: 256, used: []),
            inferred: .init(isItalicFont: false, gridAxisTags: ["wght"], namingOrderSuggested: ["wght"])
        )
        let font = FontDocument(
            id: "f1",
            sourcePath: "/tmp/font.ttf",
            axes: [
                AxisDefinition(
                    tag: "opsz",
                    min: 5,
                    default: 12,
                    max: 1200,
                    role: .instance,
                    values: []
                ),
            ]
        )

        let notes = FvarDesignSpaceAudit.informationalMessages(analysis: analysis, font: font)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("opsz default"))
        XCTAssertTrue(notes[0].contains("not rewritten on save"))
    }
}
