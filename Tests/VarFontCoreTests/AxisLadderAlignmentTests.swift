import XCTest
@testable import VarFontCore

final class AxisLadderAlignmentTests: XCTestCase {
    func testOpszExcludedFromReferenceLadder() {
        XCTAssertNil(AxisReferenceMapping.registryLadder(for: "opsz"))
        XCTAssertEqual(AxisReferenceMapping.inferKind(for: opszAxis()), .identity)
        XCTAssertTrue(AxisLadderAlignment.analyze(axis: opszAxis()).isEmpty)
    }

    func testRegistryNativeAxisProducesNoGapWarnings() {
        let axis = AxisDefinition(
            tag: "wght",
            min: 300,
            default: 400,
            max: 900,
            role: .instance,
            values: [
                AxisValue(id: "w1", value: 300, name: "Light", elidable: false, statFormat: 1),
                AxisValue(id: "w2", value: 400, name: "Regular", elidable: true, statFormat: 1),
                AxisValue(id: "w3", value: 700, name: "Bold", elidable: false, statFormat: 1),
            ]
        )
        XCTAssertTrue(AxisReferenceMapping.isRegistryNativeAxis(axis))
        XCTAssertTrue(AxisLadderAlignment.analyze(axis: axis).isEmpty)
    }

    func testPlayfairWeightSkipsUnreachableLowRegistrySteps() {
        let axis = playfairWeightAxis()
        let issues = AxisLadderAlignment.analyze(axis: axis)
        XCTAssertTrue(issues.allSatisfy { $0.kind != .misalignedStop })
        XCTAssertFalse(issues.contains { $0.idealReference == 100 })
        XCTAssertFalse(issues.contains { $0.idealReference == 200 })
        XCTAssertFalse(issues.contains { $0.idealReference == 300 })
    }

    func testPlayfairWeightReportsMissingStepsWithinSpan() {
        let axis = playfairWeightAxis()
        let missing = AxisLadderAlignment.analyze(axis: axis).filter { $0.kind == .missingIdealStop }
        XCTAssertTrue(missing.contains { $0.idealReference == 500 })
        XCTAssertTrue(missing.contains { $0.idealReference == 600 })
        XCTAssertTrue(missing.contains { $0.idealReference == 800 })
        XCTAssertTrue(missing.contains { $0.idealReference == 900 })
    }

    func testPlayfairWidthSkipsUnreachableRegistrySteps() {
        let axis = playfairWidthAxis()
        let issues = AxisLadderAlignment.analyze(axis: axis)
        XCTAssertTrue(issues.allSatisfy { $0.kind != .misalignedStop })
        XCTAssertFalse(issues.contains { $0.idealReference == 25 })
        XCTAssertFalse(issues.contains { $0.idealReference == 50 })
        XCTAssertFalse(issues.contains { $0.idealReference == 125 })
    }

    func testCannotAnchorWithoutElidableRegular() {
        let axis = AxisDefinition(
            tag: "wght",
            min: 360,
            default: 360,
            max: 900,
            role: .instance,
            values: [
                AxisValue(id: "w1", value: 500, name: "Medium", elidable: false, statFormat: 1),
            ]
        )
        let issues = AxisLadderAlignment.analyze(axis: axis)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].kind, .cannotAnchor)
    }

    // MARK: - Fixtures

    private func opszAxis() -> AxisDefinition {
        AxisDefinition(
            tag: "opsz",
            min: 5,
            default: 5,
            max: 1200,
            role: .instance,
            values: [
                AxisValue(id: "o1", value: 5, name: "Micro", elidable: false, statFormat: 1),
                AxisValue(id: "o2", value: 12, name: "Pica", elidable: true, statFormat: 1),
            ]
        )
    }

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
                AxisValue(id: "w3", value: 700, name: "Bold", elidable: false, statFormat: 1),
            ],
            referenceMapping: .stopAnchored,
            referenceMappingInferred: .stopAnchored
        )
    }
}
