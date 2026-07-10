import XCTest
@testable import VarFontCore

final class AxisTreeMergeTests: XCTestCase {
    private func wghtAxis(values: [AxisValue]) -> AxisDefinition {
        AxisDefinition(
            tag: "wght",
            min: 360,
            default: 400,
            max: 900,
            role: .instance,
            values: values
        )
    }

    private func italAxis(role: AxisRole, values: [AxisValue]) -> AxisDefinition {
        AxisDefinition(tag: "ital", displayName: "Italic", role: role, values: values)
    }

    func testPushCopiesInstanceAxisStopsFromMaster() throws {
        let masterStop = AxisValue(id: "m1", value: 700, name: "Bold", elidable: false)
        let targetStop = AxisValue(id: "t1", value: 500, name: "Medium", elidable: false)
        let master = [wghtAxis(values: [masterStop])]
        let target = [wghtAxis(values: [targetStop])]

        let merged = AxisTreeMerge.mergeAxesFromMaster(master: master, into: target, syncRoles: true)
        let wght = try XCTUnwrap(merged.first { $0.tag == "wght" })
        XCTAssertEqual(wght.values.map(\.value), [700])
        XCTAssertEqual(wght.values.map(\.name), ["Bold"])
        XCTAssertNotEqual(wght.values.first?.id, "m1")
    }

    func testPushPreservesRegistrationAxisStopsOnTarget() throws {
        let masterItal = italAxis(
            role: .designRecordOnly,
            values: [AxisValue(id: "roman", value: 0, name: "Regular", elidable: true)]
        )
        let targetItal = italAxis(
            role: .designRecordOnly,
            values: [AxisValue(id: "italic", value: 1, name: "Italic", elidable: false)]
        )
        let masterWght = wghtAxis(values: [
            AxisValue(id: "m700", value: 700, name: "Bold", elidable: false),
            AxisValue(id: "m900", value: 900, name: "Black", elidable: false),
        ])
        let targetWght = wghtAxis(values: [
            AxisValue(id: "t500", value: 500, name: "Medium", elidable: false),
        ])

        let merged = AxisTreeMerge.mergeAxesFromMaster(
            master: [masterWght, masterItal],
            into: [targetWght, targetItal],
            syncRoles: true
        )

        let ital = try XCTUnwrap(merged.first { $0.tag == "ital" })
        XCTAssertEqual(ital.values.count, 1)
        XCTAssertEqual(ital.values[0].value, 1)
        XCTAssertEqual(ital.values[0].name, "Italic")
        XCTAssertEqual(ital.values[0].id, "italic")

        let wght = try XCTUnwrap(merged.first { $0.tag == "wght" })
        XCTAssertEqual(wght.values.map(\.value), [700, 900])
    }

    func testPushDoesNotSyncRoleOntoRegistrationAxis() throws {
        let masterItal = italAxis(
            role: .instance,
            values: [AxisValue(id: "roman", value: 0, name: "Regular", elidable: true)]
        )
        let targetItal = italAxis(
            role: .designRecordOnly,
            values: [AxisValue(id: "italic", value: 1, name: "Italic", elidable: false)]
        )

        let merged = AxisTreeMerge.mergeAxesFromMaster(
            master: [masterItal],
            into: [targetItal],
            syncRoles: true
        )

        let ital = try XCTUnwrap(merged.first)
        XCTAssertEqual(ital.role, .designRecordOnly)
    }
}
