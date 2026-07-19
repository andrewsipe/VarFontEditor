import XCTest
@testable import VarFontCore

final class RegistrationAxisFactoryTests: XCTestCase {
    func testCannotDuplicateExistingAxis() {
        let axes = [AxisDefinition(tag: "wdth", role: .instance)]
        XCTAssertFalse(RegistrationAxisFactory.canAddRegistrationAxis(tag: "wdth", axes: axes))
        XCTAssertNil(RegistrationAxisFactory.templateTag(for: .width, axes: axes))
        XCTAssertEqual(RegistrationAxisFactory.templateTag(for: .slope, axes: axes), "ital")
    }

    func testSlopeTemplateSeedsRomanAndItalic() {
        let roman = RegistrationAxisFactory.makeItalAxis(isItalicFile: false)
        XCTAssertEqual(roman.tag, "ital")
        XCTAssertTrue(roman.isDesignRecordOnly)
        XCTAssertEqual(roman.values.count, 1)
        XCTAssertEqual(roman.values.first?.name, "Roman")
        XCTAssertEqual(roman.values.first?.value, 0)
        XCTAssertEqual(roman.values.first?.code, "0")
        XCTAssertTrue(roman.values.first?.elidable == true)
        XCTAssertEqual(roman.values.first?.statFormat, 3)
        XCTAssertEqual(roman.values.first?.linkedValue, 1)

        let italic = RegistrationAxisFactory.makeItalAxis(isItalicFile: true)
        XCTAssertEqual(italic.values.count, 1)
        XCTAssertEqual(italic.values.first?.name, "Italic")
        XCTAssertEqual(italic.values.first?.value, 1)
        XCTAssertEqual(italic.values.first?.code, "1")
        XCTAssertEqual(italic.values.first?.statFormat, 3)
        XCTAssertEqual(italic.values.first?.linkedValue, 0)

        XCTAssertTrue(StatFormat3Pairing.format1UpgradeWarnings(for: roman).isEmpty)
        XCTAssertTrue(StatFormat3Pairing.format1UpgradeWarnings(for: italic).isEmpty)
    }

    func testCustomAxisRejectsEmptyTag() {
        XCTAssertEqual(RegistrationAxisFactory.sanitizeAxisTag("grad!"), "grad")
        XCTAssertEqual(RegistrationAxisFactory.sanitizeAxisTag("TILT"), "TILT")
        let axis = RegistrationAxisFactory.makeCustomAxis(tag: "GRAD", displayName: "Grade")
        XCTAssertEqual(axis.tag, "GRAD")
        XCTAssertEqual(axis.displayName, "Grade")
        XCTAssertTrue(axis.isDesignRecordOnly)
    }

    func testNamedStopAxisThreadsCode() {
        let axis = RegistrationAxisFactory.makeNamedStopAxis(
            tag: "wdth",
            displayName: "Condensed",
            stopName: "Condensed",
            value: 75,
            elidable: false,
            code: "1"
        )
        XCTAssertEqual(axis.tag, "wdth")
        XCTAssertTrue(axis.isDesignRecordOnly)
        XCTAssertEqual(axis.values.count, 1)
        XCTAssertEqual(axis.values.first?.name, "Condensed")
        XCTAssertEqual(axis.values.first?.value, 75)
        XCTAssertEqual(axis.values.first?.code, "1")
    }

    func testPromoteClarifiersCreatesItalAndClearsClarifiers() throws {
        var romanRole = FileRole.master()
        romanRole.clarifiers = [FileClarifier(category: .slope, label: "", code: "0")]
        var roman = FontDocument(
            id: "roman",
            sourcePath: "/tmp/Roman.ttf",
            fileRole: romanRole,
            axes: [
                AxisDefinition(tag: "wght", role: .instance, values: [
                    AxisValue(id: "g", value: 400, name: "Regular", elidable: true),
                ]),
            ]
        )

        var italic = FontDocument(
            id: "italic",
            sourcePath: "/tmp/Italic.ttf",
            fileRole: .variant(
                masterFontID: "roman",
                clarifiers: [FileClarifier(category: .slope, label: "Italic", code: "1")]
            ),
            axes: roman.axes,
            inferredIsItalicFile: true
        )

        var project = ProjectDocument(
            schemaVersion: 1,
            familyLabel: "Test",
            naming: NamingPolicy(order: ["@pshyphen", "@code", "wght", "@slope"]),
            template: ProjectTemplate(),
            fonts: [roman, italic]
        )

        XCTAssertTrue(RegistrationAxisFactory.promoteClarifiersToRegistration(&project))
        let romanItal = try XCTUnwrap(project.fonts[0].axes.first { $0.tag == "ital" })
        let italicItal = try XCTUnwrap(project.fonts[1].axes.first { $0.tag == "ital" })
        XCTAssertEqual(romanItal.values.count, 1)
        XCTAssertEqual(romanItal.values.first?.name, "Roman")
        XCTAssertEqual(romanItal.values.first?.statFormat, 3)
        XCTAssertEqual(romanItal.values.first?.linkedValue, 1)
        XCTAssertEqual(italicItal.values.count, 1)
        XCTAssertEqual(italicItal.values.first?.name, "Italic")
        XCTAssertEqual(italicItal.values.first?.statFormat, 3)
        XCTAssertEqual(italicItal.values.first?.linkedValue, 0)
        XCTAssertEqual(project.fonts[0].fileStatRegistration["ital"], 0)
        XCTAssertEqual(project.fonts[1].fileStatRegistration["ital"], 1)
        XCTAssertTrue(project.fonts[0].fileRole?.clarifiers.isEmpty ?? false)
        XCTAssertTrue(project.fonts[1].fileRole?.clarifiers.isEmpty ?? false)
        XCTAssertTrue(project.naming.order.contains("ital"))
        XCTAssertFalse(project.naming.order.contains("@slope"))
    }

    func testWidthNamingAxisDoesNotPropagateStopToSiblingFiles() throws {
        var condensedRole = FileRole.master()
        condensedRole.clarifiers = [
            FileClarifier(category: .width, label: "Condensed", code: "1"),
        ]
        let condensed = FontDocument(
            id: "condensed",
            sourcePath: "/tmp/Condensed.ttf",
            fileRole: condensedRole,
            axes: [
                AxisDefinition(tag: "wght", role: .instance, values: [
                    AxisValue(id: "g", value: 400, name: "Regular", elidable: true),
                ]),
            ]
        )
        let expanded = FontDocument(
            id: "expanded",
            sourcePath: "/tmp/Expanded.ttf",
            fileRole: .variant(masterFontID: "condensed", clarifiers: []),
            axes: condensed.axes
        )

        var project = ProjectDocument(
            schemaVersion: 1,
            familyLabel: "Test",
            naming: NamingPolicy(order: ["@pshyphen", "@code", "wght"]),
            template: ProjectTemplate(),
            fonts: [condensed, expanded]
        )

        let axis = RegistrationAxisFactory.makeNamedStopAxis(
            tag: "wdth",
            displayName: "Condensed",
            stopName: "Condensed",
            value: 75,
            elidable: false,
            code: "1"
        )
        XCTAssertTrue(
            RegistrationAxisFactory.insertNamingAxis(
                axis,
                into: &project,
                selectedFontID: "condensed"
            )
        )

        let condensedWdth = try XCTUnwrap(project.fonts[0].axes.first { $0.tag == "wdth" })
        XCTAssertEqual(condensedWdth.values.count, 1)
        XCTAssertEqual(condensedWdth.values.first?.name, "Condensed")
        XCTAssertEqual(condensedWdth.values.first?.code, "1")
        XCTAssertEqual(project.fonts[0].fileStatRegistration["wdth"], 75)

        XCTAssertFalse(project.fonts[1].axes.contains { $0.tag == "wdth" })
        XCTAssertNil(project.fonts[1].fileStatRegistration["wdth"])
        XCTAssertTrue(project.template.axes.contains { $0.tag == "wdth" })
        XCTAssertTrue(project.naming.order.contains("wdth"))
        XCTAssertEqual(project.fonts[0].statDesignAxisTags, ["wght", "wdth"])
    }

    /// The override lets the user correct a wrong Roman/Italic auto-detection on the file
    /// they're actively editing, without disturbing how siblings are auto-detected.
    func testItalicOverrideAppliesOnlyToSelectedFont() throws {
        let roman = FontDocument(id: "roman", sourcePath: "/tmp/Roman.ttf")
        let sibling = FontDocument(id: "sibling", sourcePath: "/tmp/Sibling.ttf")

        var project = ProjectDocument(
            schemaVersion: 1,
            familyLabel: "Test",
            naming: NamingPolicy(order: ["@pshyphen", "@code", "wght"]),
            template: ProjectTemplate(),
            fonts: [roman, sibling]
        )

        let axis = RegistrationAxisFactory.makeTemplateAxis(kind: .slope)
        XCTAssertTrue(
            RegistrationAxisFactory.insertNamingAxis(
                axis,
                into: &project,
                selectedFontID: "roman",
                italicOverride: true
            )
        )

        let romanItal = try XCTUnwrap(project.fonts[0].axes.first { $0.tag == "ital" })
        XCTAssertEqual(romanItal.values.first?.name, "Italic")
        XCTAssertEqual(project.fonts[0].fileStatRegistration["ital"], 1)

        let siblingItal = try XCTUnwrap(project.fonts[1].axes.first { $0.tag == "ital" })
        XCTAssertEqual(siblingItal.values.first?.name, "Roman")
        XCTAssertEqual(project.fonts[1].fileStatRegistration["ital"], 0)
    }
}
