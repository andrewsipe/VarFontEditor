import XCTest
@testable import VarFontCore

final class Format3StopTests: XCTestCase {
    func testPlayfairImportPreservesLinkedValue() throws {
        let analysis = try FixtureLoader.decode(FontAnalysis.self, from: "playfair-roman-analysis.json")
        let project = ProjectImporter.newProject(
            from: analysis,
            sourceURL: URL(fileURLWithPath: analysis.source.path)
        )
        let wght = project.fonts[0].axes.first { $0.tag == "wght" }
        let normal = wght?.values.first { $0.name == "Normal" }
        XCTAssertEqual(normal?.statFormat, 3)
        XCTAssertEqual(normal?.linkedValue, 700)
    }

    func testDisplayRowsGroupsFormat3Pair() {
        let stops = [
            AxisValue(id: "w1", value: 400, name: "Normal", elidable: true, statFormat: 3, linkedValue: 700),
            AxisValue(id: "w2", value: 700, name: "Bold", elidable: false, statFormat: 1),
            AxisValue(id: "w3", value: 360, name: "SemiLight", elidable: false, statFormat: 1),
        ]
        let rows = StatFormat3Pairing.displayRows(for: stops)
        XCTAssertEqual(rows.count, 2)
        if case .pair(let primary, let linked) = rows[0].kind {
            XCTAssertEqual(primary.name, "Normal")
            XCTAssertEqual(linked?.name, "Bold")
        } else {
            XCTFail("Expected pair row first")
        }
        if case .single(let stop) = rows[1].kind {
            XCTAssertEqual(stop.name, "SemiLight")
        } else {
            XCTFail("Expected single row second")
        }
    }

    func testOrphanLinkWarning() {
        let axis = AxisDefinition(
            tag: "wght",
            min: 100,
            role: .instance,
            values: [
                AxisValue(id: "a", value: 400, name: "Normal", elidable: true, statFormat: 3, linkedValue: 999),
            ]
        )
        let warnings = StatFormat3Pairing.orphanLinkWarnings(for: axis)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings[0].code, "orphan_stat_link")
    }

    func testCommitRequestPreservesLinkedValue() throws {
        let request = try FixtureLoader.decode(CommitRequest.self, from: "playfair-roman-commit-request.json")
        let wght = request.axes.first { $0.tag == "wght" }
        let normal = wght?.values.first { $0.statFormat == 3 }
        XCTAssertEqual(normal?.linkedValue, 700)
    }
}
