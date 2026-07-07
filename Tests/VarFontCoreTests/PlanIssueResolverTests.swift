import XCTest
@testable import VarFontCore

final class PlanIssueResolverTests: XCTestCase {
    private func italAxis(stops: [AxisValue]) -> AxisDefinition {
        AxisDefinition(
            tag: "ital",
            role: .designRecordOnly,
            values: stops
        )
    }

    func testRegistrationMismatchAutoFixesWhenRomanStopPresent() {
        var font = FontDocument(
            id: "f1",
            sourcePath: "/tmp/PlayfairRomanVF.woff2",
            axes: [
                italAxis(stops: [
                    AxisValue(id: "r", value: 0, name: "Roman", elidable: true),
                    AxisValue(id: "i", value: 1, name: "Italic", elidable: false),
                ]),
            ],
            fileStatRegistration: ["ital": 1],
            inferredIsItalicFile: false
        )

        let result = PlanIssueResolver.applySafeAutoFixes(to: &font)
        XCTAssertGreaterThan(result.appliedCount, 0)
        XCTAssertEqual(font.fileStatRegistration["ital"], 0)
        let warnings = PlanIssueResolver.visibleWarnings(for: font)
        XCTAssertFalse(warnings.contains { $0.code == "registration_mismatch" })
    }

    func testRegistrationMismatchOnlyItalicStopOffersRenameNotSilentAuto() throws {
        var font = FontDocument(
            id: "f1",
            sourcePath: "/tmp/PlayfairRomanVF.woff2",
            axes: [
                italAxis(stops: [
                    AxisValue(id: "i", value: 1, name: "Italic", elidable: false),
                ]),
            ],
            fileStatRegistration: ["ital": 1],
            inferredIsItalicFile: false
        )

        let result = PlanIssueResolver.applySafeAutoFixes(to: &font)
        XCTAssertEqual(result.appliedCount, 0)

        let warning = RegistrationAxisSupport.registrationWarnings(font: font, analysis: nil).first
        XCTAssertEqual(warning?.code, "registration_mismatch")
        let proposals = PlanIssueResolver.proposals(for: try XCTUnwrap(warning), font: font)
        XCTAssertTrue(proposals.contains { $0.title == "Rename stop to Roman" && $0.isRecommended })
        XCTAssertTrue(proposals.contains { $0.title == "Keep current registration" })
    }

    func testItalConventionSoleRomanAtOneAutoFixes() {
        var font = FontDocument(
            id: "milgram",
            sourcePath: "/tmp/Milgram-Variable.ttf",
            axes: [
                italAxis(stops: [
                    AxisValue(id: "r", value: 1, name: "Roman", elidable: true),
                ]),
            ],
            fileStatRegistration: ["ital": 1],
            inferredIsItalicFile: false
        )

        let result = PlanIssueResolver.applySafeAutoFixes(to: &font)
        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(font.axes[0].values[0].value, 0)
        XCTAssertEqual(font.fileStatRegistration["ital"], 0)
    }

    func testOrphanF3ConvertToFormat1() throws {
        var font = FontDocument(
            id: "f1",
            sourcePath: "/tmp/font.ttf",
            axes: [
                italAxis(stops: [
                    AxisValue(
                        id: "r",
                        value: 0,
                        name: "Roman",
                        elidable: true,
                        statFormat: 3,
                        linkedValue: 1
                    ),
                ]),
            ]
        )

        let warning = StatFormat3Pairing.orphanLinkWarnings(for: font.axes[0]).first
        XCTAssertEqual(warning?.code, "orphan_stat_link")

        let proposal = PlanIssueResolver.proposals(for: try XCTUnwrap(warning), font: font)
            .first { $0.title == "Convert to Format 1" }
        XCTAssertNotNil(proposal)

        PlanIssueResolver.apply(try XCTUnwrap(proposal).action, to: &font)
        XCTAssertEqual(font.axes[0].values[0].statFormat, 1)
        XCTAssertNil(font.axes[0].values[0].linkedValue)
    }

    func testRevalueStopSyncsRegistrationWhenRegistered() {
        var font = FontDocument(
            id: "f1",
            sourcePath: "/tmp/font.ttf",
            axes: [
                italAxis(stops: [
                    AxisValue(id: "r", value: 1, name: "Roman", elidable: true),
                ]),
            ],
            fileStatRegistration: ["ital": 1]
        )

        PlanIssueResolver.apply(
            .revalueStop(axisTag: "ital", stopID: "r", newValue: 0),
            to: &font
        )
        XCTAssertEqual(font.axes[0].values[0].value, 0)
        XCTAssertEqual(font.fileStatRegistration["ital"], 0)
    }

    func testCompoundOrphanItalProposal() throws {
        var font = FontDocument(
            id: "playfair",
            sourcePath: "/tmp/PlayfairRomanVF.woff2",
            axes: [
                italAxis(stops: [
                    AxisValue(
                        id: "r",
                        value: 1,
                        name: "Roman",
                        elidable: true,
                        statFormat: 3,
                        linkedValue: 99
                    ),
                ]),
            ],
            fileStatRegistration: ["ital": 1],
            inferredIsItalicFile: false
        )

        let orphan = try XCTUnwrap(StatFormat3Pairing.orphanLinkWarnings(for: font.axes[0]).first)
        let proposals = PlanIssueResolver.proposals(for: orphan, font: font)
        XCTAssertEqual(proposals.count, 1)
        XCTAssertTrue(proposals[0].title.contains("Format 1"))
        XCTAssertTrue(proposals[0].title.contains("Roman"))

        PlanIssueResolver.apply(proposals[0].action, to: &font)
        XCTAssertEqual(font.axes[0].values[0].statFormat, 1)
        XCTAssertEqual(font.axes[0].values[0].value, 0)
        XCTAssertEqual(font.fileStatRegistration["ital"], 0)
    }

    func testAcknowledgeIssueDismissesWarning() throws {
        var font = FontDocument(
            id: "f1",
            sourcePath: "/tmp/font.ttf",
            axes: [
                italAxis(stops: [
                    AxisValue(
                        id: "r",
                        value: 0,
                        name: "Roman",
                        elidable: true,
                        statFormat: 3,
                        linkedValue: 1
                    ),
                ]),
            ]
        )

        let warning = try XCTUnwrap(StatFormat3Pairing.orphanLinkWarnings(for: font.axes[0]).first)
        let key = PlanIssueCodes.issueKey(for: warning)
        PlanIssueResolver.apply(.acknowledgeIssue(issueKey: key), to: &font)
        XCTAssertTrue(font.dismissedPlanIssues.contains(key))

        let visible = PlanIssueResolver.visibleWarnings(for: font)
        XCTAssertFalse(visible.contains { PlanIssueCodes.issueKey(for: $0) == key })
    }

    func testDuplicateComposedNameOffersAxisNeutralsForNouveau() {
        let font = FontDocument(
            id: "nouveau",
            sourcePath: "/tmp/Nouveau-Variable.ttf",
            axes: [
                AxisDefinition(
                    tag: "wdth",
                    role: .instance,
                    values: [
                        AxisValue(id: "w1", value: 100, name: "Regular", elidable: true),
                        AxisValue(id: "w2", value: 150, name: "Expanded", elidable: false),
                    ]
                ),
            ]
        )
        let warning = PlanWarning(
            code: "duplicate_composed_name",
            message: "Composed name “Regular Regular” is used by 6 instances."
        )
        let proposals = PlanIssueResolver.proposals(for: warning, font: font)
        XCTAssertEqual(proposals.first?.title, "Align baseline labels")
        XCTAssertEqual(proposals.first?.isRecommended, true)
    }

    func testDuplicateComposedNameOffersRenameFromValuesForNouveauLED() {
        let font = FontDocument(
            id: "led",
            sourcePath: "/tmp/NouveauLED-Variable.ttf",
            axes: [
                AxisDefinition(
                    tag: "wght",
                    role: .instance,
                    values: [
                        AxisValue(id: "w1", value: 0, name: "Regular", elidable: true),
                        AxisValue(id: "w2", value: 250, name: "Regular", elidable: false),
                    ]
                ),
            ]
        )
        let warning = PlanWarning(
            code: "duplicate_composed_name",
            message: "Composed name “Regular” is used by 30 instances."
        )
        let proposals = PlanIssueResolver.proposals(for: warning, font: font)
        XCTAssertEqual(proposals.first?.title, "Rename stops from values")
    }

    func testDuplicateComposedNameFallsBackToRenameFromValuesAfterPartialFix() {
        let font = FontDocument(
            id: "led-partial",
            sourcePath: "/tmp/NouveauLED-Variable.ttf",
            axes: [
                AxisDefinition(
                    tag: "wght",
                    role: .instance,
                    values: [
                        AxisValue(id: "w1", value: 0, name: "Regular", elidable: true),
                        AxisValue(id: "w2", value: 250, name: "250", elidable: false),
                    ]
                ),
                AxisDefinition(
                    tag: "FLOR",
                    role: .instance,
                    values: [
                        AxisValue(id: "f1", value: 0, name: "0", elidable: true),
                        AxisValue(id: "f2", value: 250, name: "250", elidable: false),
                    ]
                ),
            ]
        )
        let warning = PlanWarning(
            code: "duplicate_composed_name",
            message: "4 composed names are duplicated."
        )
        let proposals = PlanIssueResolver.proposals(for: warning, font: font)
        XCTAssertEqual(proposals.first?.title, "Adjust stops manually")
        XCTAssertNil(PlanIssueResolver.recommendedProposal(for: warning, font: font))
        XCTAssertFalse(AxisStopNamingDefaults.hasAxisNeutralMismatch(font))
    }

    func testDuplicateComposedWithValueConflictsOffersOpenConflicts() {
        let font = FontDocument(
            id: "reflex",
            sourcePath: "/tmp/Reflex.ttf",
            axes: [
                AxisDefinition(
                    tag: "wdth",
                    role: .instance,
                    values: [
                        AxisValue(id: "w1", value: 100, name: "Normal", elidable: true),
                        AxisValue(id: "w2", value: 100, name: "Bold", elidable: false),
                    ]
                ),
            ]
        )
        let warning = PlanWarning(
            code: "duplicate_composed_name",
            message: "Composed name “Normal Regular” is used by 6 instances."
        )
        let proposals = PlanIssueResolver.proposals(for: warning, font: font)
        XCTAssertEqual(proposals.first?.title, "Resolve value conflicts")
        XCTAssertEqual(proposals.first?.isRecommended, true)
        if case .openAxisConflicts(let tag) = proposals.first?.action {
            XCTAssertEqual(tag, "wdth")
        } else {
            XCTFail("Expected openAxisConflicts action")
        }
        XCTAssertNotNil(PlanIssueResolver.recommendedProposal(for: warning, font: font))
    }

    func testEmptyInstanceAxisProposalsWithoutScaleFallsBackToStatOnly() {
        let font = FontDocument(
            id: "empty",
            sourcePath: "/tmp/empty.ttf",
            axes: [
                AxisDefinition(tag: "wdth", role: .instance, values: []),
            ]
        )
        let warning = PlanWarning(
            code: "empty_instance_axis",
            axis: "wdth",
            message: "Instance axis 'wdth' has no stops."
        )
        let proposals = PlanIssueResolver.proposals(for: warning, font: font)
        XCTAssertEqual(proposals.first(where: \.isRecommended)?.title, "Switch to STAT-only")
        XCTAssertTrue(proposals.contains { proposal in
            if case .insertAxisStop(let tag, _, _) = proposal.action { return tag == "wdth" }
            return false
        })
    }

    func testEmptyInstanceAxisOffersFillPlannerOptions() throws {
        let axis = AxisDefinition(tag: "wght", min: 0, default: 0, max: 200, role: .instance, values: [])
        let options = try XCTUnwrap(AxisStopFillPlanner.options(for: axis))
        XCTAssertEqual(options.recommendedCounts, [3, 6, 9, 12])
        XCTAssertEqual(options.defaultCount, 6)
    }

    func testEmptyInstanceAxisApplyInteractiveFillValues() {
        var font = FontDocument(
            id: "empty",
            sourcePath: "/tmp/Flux.ttf",
            axes: [
                AxisDefinition(tag: "wght", min: 0, default: 0, max: 200, role: .instance, values: []),
            ]
        )
        let values = AxisStopFillPlanner.values(for: font.axes[0], count: 5) ?? []
        PlanIssueResolver.apply(.insertAxisStops(axisTag: "wght", values: values), to: &font)
        XCTAssertEqual(font.axes[0].values.map(\.value), [0, 50, 100, 150, 200])
        XCTAssertEqual(font.axes[0].values.map(\.name), ["0", "50", "100", "150", "200"])
    }

    func testEmptyInstanceAxisApplyIntervalFillValues() {
        var font = FontDocument(
            id: "empty",
            sourcePath: "/tmp/Flux.ttf",
            axes: [
                AxisDefinition(tag: "wght", min: 0, default: 0, max: 200, role: .instance, values: []),
            ]
        )
        let values = AxisStopFillPlanner.values(for: font.axes[0], interval: 100) ?? []
        PlanIssueResolver.apply(.insertAxisStops(axisTag: "wght", values: values), to: &font)
        XCTAssertEqual(font.axes[0].values.map(\.value), [0, 100, 200])
    }

    func testEmptyInstanceAxisApplyAddsStop() {
        var font = FontDocument(
            id: "empty",
            sourcePath: "/tmp/empty.ttf",
            axes: [
                AxisDefinition(tag: "wdth", min: 75, default: 100, max: 125, role: .instance, values: []),
            ]
        )
        let warning = PlanWarning(
            code: "empty_instance_axis",
            axis: "wdth",
            message: "Instance axis 'wdth' has no stops."
        )
        guard let proposal = PlanIssueResolver.proposals(for: warning, font: font).first(where: {
            if case .insertAxisStop = $0.action { return true }
            return false
        }) else {
            XCTFail("Missing insertAxisStop proposal")
            return
        }
        PlanIssueResolver.apply(proposal.action, to: &font)
        XCTAssertEqual(font.axes[0].values.count, 1)
    }
}
