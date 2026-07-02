import XCTest
@testable import VarFontCore

final class ReferenceMappingTests: XCTestCase {
    func testIdentityForRegistryWeightScale() {
        let axis = AxisDefinition(
            tag: "wght",
            min: 100,
            default: 400,
            max: 900,
            role: .instance,
            values: []
        )
        XCTAssertEqual(AxisReferenceMapping.inferKind(for: axis), .identity)
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(700, axis: axis), 700)
    }

    func testPlayfairWidthUsesStopAnchoredRegistryLadder() {
        let axis = playfairWidthAxis()
        XCTAssertEqual(AxisReferenceMapping.inferKind(for: axis), .stopAnchored)

        XCTAssertEqual(AxisReferenceMapping.nativeToReference(88, axis: axis), 87.5, accuracy: 0.01)
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(100, axis: axis), 100, accuracy: 0.01)
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(113, axis: axis), 112.5, accuracy: 0.01)
    }

    func testPlayfairWeightUsesStopAnchoredRegistryLadder() {
        let axis = playfairWeightAxis()
        XCTAssertEqual(AxisReferenceMapping.inferKind(for: axis), .stopAnchored)

        XCTAssertEqual(AxisReferenceMapping.nativeToReference(360, axis: axis), 350, accuracy: 0.01)
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(400, axis: axis), 400, accuracy: 0.01)
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(500, axis: axis), 500, accuracy: 0.01)
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(600, axis: axis), 600, accuracy: 0.01)
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(700, axis: axis), 700, accuracy: 0.01)
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(800, axis: axis), 800, accuracy: 0.01)
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(900, axis: axis), 900, accuracy: 0.01)
    }

    func testPlayfairWeightDoesNotCollapseLowStopsToRegular() {
        let axis = playfairWeightAxis()
        let semiLight = AxisReferenceMapping.nativeToReference(360, axis: axis)
        let normal = AxisReferenceMapping.nativeToReference(400, axis: axis)
        XCTAssertLessThan(semiLight, normal)
        XCTAssertEqual(semiLight, 350, accuracy: 0.01)
        XCTAssertEqual(normal, 400, accuracy: 0.01)
    }

    func testReferenceToNativeRoundTripOnPlayfairWidth() {
        let axis = playfairWidthAxis()
        for reference in [75.0, 87.5, 100.0, 112.5] {
            let native = AxisReferenceMapping.referenceToNative(reference, axis: axis)
            let back = AxisReferenceMapping.nativeToReference(native, axis: axis)
            XCTAssertEqual(back, reference, accuracy: 0.5)
        }
    }

    func testReferenceToNativeRoundTripOnPlayfairWeight() {
        let axis = playfairWeightAxis()
        for reference in [350.0, 400.0, 500.0, 700.0, 900.0] {
            let native = AxisReferenceMapping.referenceToNative(reference, axis: axis)
            let back = AxisReferenceMapping.nativeToReference(native, axis: axis)
            XCTAssertEqual(back, reference, accuracy: 0.5)
        }
    }

    func testMilgramExtraBoldUsesValueAnchorNotBoldName() {
        let axis = AxisDefinition(
            tag: "wght",
            min: 300,
            default: 300,
            max: 900,
            role: .instance,
            values: [
                AxisValue(id: "w1", value: 300, name: "Light", elidable: false, statFormat: 1),
                AxisValue(id: "w2", value: 400, name: "Regular", elidable: true, statFormat: 3, linkedValue: 700),
                AxisValue(id: "w3", value: 800, name: "X-Bold", elidable: false, statFormat: 1),
                AxisValue(id: "w4", value: 900, name: "Black", elidable: false, statFormat: 1),
            ],
            referenceMapping: .stopAnchored,
            referenceMappingInferred: .stopAnchored
        )
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(800, axis: axis), 800, accuracy: 0.01)
    }

    func testNouveauQuellstiftThinKeeps200WhenOnLadder() {
        let axis = AxisDefinition(
            tag: "wght",
            min: 100,
            default: 100,
            max: 700,
            role: .instance,
            values: [
                AxisValue(id: "w1", value: 100, name: "Hair", elidable: false, statFormat: 1),
                AxisValue(id: "w2", value: 200, name: "Thin", elidable: false, statFormat: 1),
                AxisValue(id: "w3", value: 400, name: "Regular", elidable: true, statFormat: 3, linkedValue: 700),
            ],
            referenceMapping: .stopAnchored,
            referenceMappingInferred: .stopAnchored
        )
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(100, axis: axis), 100, accuracy: 0.01)
        XCTAssertEqual(AxisReferenceMapping.nativeToReference(200, axis: axis), 200, accuracy: 0.01)
    }

    func testMelangeWidthStaysIdentity() {
        let axis = AxisDefinition(
            tag: "wdth",
            min: 50,
            default: 200,
            max: 200,
            role: .instance,
            values: [
                AxisValue(id: "d1", value: 50, name: "Ultra Condensed", elidable: false, statFormat: 2, rangeMin: 50, rangeMax: 68.47),
                AxisValue(id: "d2", value: 162.31, name: "Normal", elidable: true, statFormat: 2, rangeMin: 143.47, rangeMax: 181.16),
            ]
        )
        XCTAssertEqual(AxisReferenceMapping.inferKind(for: axis), .identity)
    }

    func testImportInfersStopAnchoredForPlayfairWidth() throws {
        let analysis = try FixtureLoader.decode(FontAnalysis.self, from: "playfair-roman-analysis.json")
        let project = ProjectImporter.newProject(
            from: analysis,
            sourceURL: URL(fileURLWithPath: analysis.source.path)
        )
        let wdth = project.fonts[0].axes.first { $0.tag == "wdth" }
        XCTAssertEqual(wdth?.referenceMapping, .stopAnchored)
        XCTAssertGreaterThanOrEqual(wdth?.referenceAnchors.count ?? 0, 2)
    }

    // MARK: - Fixtures

    private func playfairWidthAxis() -> AxisDefinition {
        AxisDefinition(
            tag: "wdth",
            min: 88,
            default: 88,
            max: 113,
            role: .instance,
            values: [
                AxisValue(id: "d1", value: 88, name: "SemiCond", elidable: false, statFormat: 1),
                AxisValue(id: "d2", value: 100, name: "Normal", elidable: true, statFormat: 1),
                AxisValue(id: "d3", value: 113, name: "SemiExp", elidable: false, statFormat: 1),
            ],
            referenceMapping: .stopAnchored,
            referenceMappingInferred: .stopAnchored
        )
    }

    private func playfairWeightAxis() -> AxisDefinition {
        AxisDefinition(
            tag: "wght",
            min: 360,
            default: 360,
            max: 900,
            role: .instance,
            values: [
                AxisValue(id: "w1", value: 360, name: "SemiLight", elidable: false, statFormat: 1),
                AxisValue(id: "w2", value: 400, name: "Normal", elidable: true, statFormat: 3, linkedValue: 700),
                AxisValue(id: "w3", value: 500, name: "Medium", elidable: false, statFormat: 1),
                AxisValue(id: "w4", value: 600, name: "SemiBold", elidable: false, statFormat: 1),
                AxisValue(id: "w5", value: 700, name: "Bold", elidable: false, statFormat: 1),
                AxisValue(id: "w6", value: 800, name: "ExBold", elidable: false, statFormat: 1),
                AxisValue(id: "w7", value: 900, name: "Black", elidable: false, statFormat: 1),
            ],
            referenceMapping: .stopAnchored,
            referenceMappingInferred: .stopAnchored
        )
    }
}
