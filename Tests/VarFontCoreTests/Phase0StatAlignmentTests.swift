import XCTest
@testable import VarFontCore

final class ElidedFallbackResolverTests: XCTestCase {
    func testRomanResolvesToRegularWhenAllElidable() {
        let axes = [
            AxisDefinition(
                tag: "wght",
                role: .instance,
                values: [
                    AxisValue(id: "w1", value: 400, name: "Regular", elidable: true),
                    AxisValue(id: "w2", value: 700, name: "Bold", elidable: false),
                ]
            ),
            AxisDefinition(
                tag: "ital",
                role: .designRecordOnly,
                values: [
                    AxisValue(id: "i0", value: 0, name: "Roman", elidable: true),
                ]
            ),
        ]
        let result = ElidedFallbackResolver.resolve(
            axes: axes,
            namingOrder: ["ital", "wght"],
            fileStatRegistration: ["ital": 0],
            sourceElidedFallback: "Regular",
            fileRole: nil
        )
        XCTAssertEqual(result.value, "Regular")
        XCTAssertFalse(result.inferred)
    }

    func testInferredWhenNoSourceFallback() {
        let axes = [
            AxisDefinition(
                tag: "wght",
                role: .instance,
                values: [AxisValue(id: "w1", value: 400, name: "Regular", elidable: true)]
            ),
        ]
        let result = ElidedFallbackResolver.resolve(
            axes: axes,
            namingOrder: ["wght"],
            fileStatRegistration: [:],
            sourceElidedFallback: nil,
            fileRole: nil
        )
        XCTAssertEqual(result.value, "Regular")
        XCTAssertTrue(result.inferred)
    }
}

final class StatParserFormat4Tests: XCTestCase {
    func testParsesFormat4CompoundEntry() {
        var data = Data()
        func appendUInt16(_ v: UInt16) {
            data.append(UInt8((v >> 8) & 0xFF))
            data.append(UInt8(v & 0xFF))
        }
        func appendUInt32(_ v: UInt32) {
            data.append(UInt8((v >> 24) & 0xFF))
            data.append(UInt8((v >> 16) & 0xFF))
            data.append(UInt8((v >> 8) & 0xFF))
            data.append(UInt8(v & 0xFF))
        }
        func appendFixed(_ value: Double) {
            let fixed = Int32(value * 65536.0)
            appendUInt32(UInt32(bitPattern: fixed))
        }

        appendUInt32(0x0001_0002)
        appendUInt16(8)
        appendUInt16(1)
        appendUInt32(22)
        appendUInt16(1)
        appendUInt32(30)
        appendUInt16(0)

        appendUInt16(0)

        data.append(contentsOf: [0x77, 0x67, 0x68, 0x74])
        appendUInt16(256)
        appendUInt16(0)

        appendUInt16(2)

        appendUInt16(4)
        appendUInt16(1)
        appendUInt16(0)
        appendUInt16(0)
        appendUInt16(300)
        appendFixed(700)

        guard let parsed = StatParser.parse(data) else {
            XCTFail("parse returned nil")
            return
        }
        XCTAssertEqual(parsed.values.count, 0)
        XCTAssertEqual(parsed.compoundValues.count, 1)
        XCTAssertEqual(parsed.compoundValues.first?.axisIndices, [0])
        XCTAssertEqual(parsed.compoundValues.first?.axisValues.first ?? 0, 700, accuracy: 0.001)
    }
}
