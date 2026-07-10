import XCTest
@testable import VarFontCore

final class OpenTypeAxisAuditTests: XCTestCase {
    func testFvarMissingFromStatWarning() {
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
                    values: [AxisValue(id: "w1", value: 400, name: "Regular", elidable: true)]
                ),
                AxisDefinition(
                    tag: "wdth",
                    min: 75,
                    default: 100,
                    max: 125,
                    role: .instance,
                    values: [AxisValue(id: "d1", value: 100, name: "Normal", elidable: false)]
                ),
            ],
            statDesignAxisTags: ["wght"]
        )

        let warnings = OpenTypeAxisAudit.fvarStatParityWarnings(font: font)
        XCTAssertEqual(warnings.map(\.code), ["fvar_missing_from_stat"])
        XCTAssertEqual(warnings.first?.axis, "wdth")
    }

    func testItalSlntCoexistenceWarning() {
        let font = FontDocument(
            id: "f1",
            sourcePath: "/tmp/font.ttf",
            axes: [
                AxisDefinition(
                    tag: "ital",
                    role: .designRecordOnly,
                    values: [AxisValue(id: "i1", value: 1, name: "Italic", elidable: false)]
                ),
                AxisDefinition(
                    tag: "slnt",
                    min: -12,
                    default: 0,
                    max: 0,
                    role: .instance,
                    values: [AxisValue(id: "s1", value: -12, name: "Oblique", elidable: false)]
                ),
            ],
            fileStatRegistration: ["ital": 1]
        )

        let warnings = OpenTypeAxisAudit.italSlntCoexistenceWarnings(
            font: font,
            namingOrder: ["wght", "slnt", "ital"]
        )
        XCTAssertTrue(warnings.isEmpty)
    }

    func testItalSlntCoexistenceWarnsWhenBothVaryInstances() {
        let font = FontDocument(
            id: "f1",
            sourcePath: "/tmp/font.ttf",
            axes: [
                AxisDefinition(
                    tag: "ital",
                    min: 0,
                    default: 0,
                    max: 1,
                    role: .instance,
                    values: [
                        AxisValue(id: "r", value: 0, name: "Roman", elidable: true),
                        AxisValue(id: "i", value: 1, name: "Italic", elidable: false),
                    ]
                ),
                AxisDefinition(
                    tag: "slnt",
                    min: -12,
                    default: 0,
                    max: 0,
                    role: .instance,
                    values: [AxisValue(id: "s1", value: -12, name: "Oblique", elidable: false)]
                ),
            ]
        )

        let warnings = OpenTypeAxisAudit.italSlntCoexistenceWarnings(
            font: font,
            namingOrder: ["wght", "slnt", "ital"]
        )
        XCTAssertEqual(warnings.first?.code, "ital_slnt_coexistence")
    }

    func testDefaultInstanceExcludedWarning() {
        let font = FontDocument(
            id: "f1",
            sourcePath: "/tmp/font.ttf",
            axes: [
                AxisDefinition(
                    tag: "wght",
                    min: 400,
                    default: 400,
                    max: 700,
                    role: .instance,
                    values: [
                        AxisValue(id: "w1", value: 400, name: "Regular", elidable: true),
                        AxisValue(id: "w2", value: 700, name: "Bold", elidable: false),
                    ]
                ),
            ],
            excludedInstanceKeys: ["wght:400"]
        )
        let instances = InstancePlanner.plan(font: font, naming: NamingPolicy(order: ["wght"])).instances

        let warnings = OpenTypeAxisAudit.defaultInstanceWarnings(font: font, instances: instances)
        XCTAssertEqual(warnings.first?.code, "default_instance_excluded")
    }

    func testRegisteredDefaultInformationalMessage() {
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
                    default: 350,
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
                    default: 350,
                    max: 900,
                    role: .instance,
                    values: []
                ),
            ]
        )

        let messages = OpenTypeAxisAudit.registeredDefaultMessages(analysis: analysis, font: font)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("wght fvar default is 350"))
        XCTAssertTrue(messages[0].contains("registry requires 400"))
    }

    func testWghtFormat3ConventionLinkIsNotOrphan() {
        let axis = AxisDefinition(
            tag: "wght",
            role: .instance,
            values: [
                AxisValue(
                    id: "bold",
                    value: 700,
                    name: "Bold",
                    elidable: false,
                    statFormat: 3,
                    linkedValue: 400
                ),
            ]
        )
        XCTAssertTrue(StatFormat3Pairing.isConventionStyleLink(axis: axis, stop: axis.values[0]))
        XCTAssertTrue(StatFormat3Pairing.orphanLinkWarnings(for: axis).isEmpty)
    }
}
