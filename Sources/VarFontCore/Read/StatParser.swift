import Foundation

struct StatDesignAxis: Sendable {
    var tag: String
    var nameID: Int
    var ordering: Int
}

struct ParsedStatValue: Sendable {
    var format: Int
    var axisIndex: Int
    var flags: UInt16
    var nameID: Int
    var value: Double?
    var linkedValue: Double?
    var rangeMin: Double?
    var nominal: Double?
    var rangeMax: Double?

    var elidable: Bool { flags & 0x2 != 0 }
}

struct StatParseResult: Sendable {
    var designAxes: [StatDesignAxis]
    var values: [ParsedStatValue]
    var elidedFallbackNameID: Int?
}

enum StatParser {
    static func parse(_ data: Data) -> StatParseResult? {
        guard data.count >= 16 else { return nil }

        let version = OpenTypeBinary.readUInt32(data, 0)
        let designAxisSize = Int(OpenTypeBinary.readUInt16(data, 4))
        let designAxisCount = Int(OpenTypeBinary.readUInt16(data, 6))

        let designAxisOffset: Int
        let axisValueCount: Int
        let axisValueArrayOffset: Int
        let elidedFallbackNameID: Int?
        let offsetsRelativeToArrayBase: Bool

        if version >= 0x0001_0001 {
            guard data.count >= 22 else { return nil }
            designAxisOffset = Int(OpenTypeBinary.readUInt32(data, 8))
            axisValueCount = Int(OpenTypeBinary.readUInt16(data, 12))
            let offset32 = Int(OpenTypeBinary.readUInt32(data, 16))
            if offset32 > 0, offset32 < data.count {
                axisValueArrayOffset = offset32
                let id = Int(OpenTypeBinary.readUInt16(data, 20))
                elidedFallbackNameID = id > 0 ? id : nil
            } else {
                // Some production fonts pack offset (uint16) + elided fallback (uint16) at 16–19
                // instead of a full Offset32 at 16 and NameID at 20.
                axisValueArrayOffset = Int(OpenTypeBinary.readUInt16(data, 16))
                let id = Int(OpenTypeBinary.readUInt16(data, 18))
                elidedFallbackNameID = id > 0 ? id : nil
            }
            offsetsRelativeToArrayBase = version < 0x0001_0002
        } else {
            designAxisOffset = Int(OpenTypeBinary.readUInt16(data, 8))
            axisValueCount = Int(OpenTypeBinary.readUInt16(data, 10))
            axisValueArrayOffset = Int(OpenTypeBinary.readUInt16(data, 12))
            elidedFallbackNameID = nil
            offsetsRelativeToArrayBase = true
        }

        guard designAxisCount > 0, designAxisSize >= 8 else {
            return StatParseResult(designAxes: [], values: [], elidedFallbackNameID: elidedFallbackNameID)
        }

        var designAxes: [StatDesignAxis] = []
        for index in 0..<designAxisCount {
            let base = designAxisOffset + index * designAxisSize
            guard base + 8 <= data.count else { break }
            designAxes.append(
                StatDesignAxis(
                    tag: OpenTypeBinary.readTag(data, base),
                    nameID: Int(OpenTypeBinary.readUInt16(data, base + 4)),
                    ordering: Int(OpenTypeBinary.readUInt16(data, base + 6))
                )
            )
        }

        var values: [ParsedStatValue] = []
        guard axisValueCount > 0,
              axisValueArrayOffset > 0,
              axisValueArrayOffset + axisValueCount * 2 <= data.count else {
            return StatParseResult(
                designAxes: designAxes,
                values: values,
                elidedFallbackNameID: elidedFallbackNameID
            )
        }

        for index in 0..<axisValueCount {
            let rawOffset = Int(OpenTypeBinary.readUInt16(data, axisValueArrayOffset + index * 2))
            guard rawOffset > 0 else { continue }
            let recordOffset = offsetsRelativeToArrayBase
                ? axisValueArrayOffset + rawOffset
                : rawOffset
            guard recordOffset + 6 <= data.count else { continue }
            if let parsed = parseAxisValue(data: data, offset: recordOffset) {
                values.append(parsed)
            }
        }

        return StatParseResult(
            designAxes: designAxes,
            values: values,
            elidedFallbackNameID: elidedFallbackNameID
        )
    }

    private static func parseAxisValue(data: Data, offset: Int) -> ParsedStatValue? {
        let format = Int(OpenTypeBinary.readUInt16(data, offset))
        let axisIndex = Int(OpenTypeBinary.readUInt16(data, offset + 2))
        let flags = OpenTypeBinary.readUInt16(data, offset + 4)

        switch format {
        case 1:
            guard offset + 12 <= data.count else { return nil }
            return ParsedStatValue(
                format: format,
                axisIndex: axisIndex,
                flags: flags,
                nameID: Int(OpenTypeBinary.readUInt16(data, offset + 6)),
                value: OpenTypeBinary.readFixed(data, offset + 8),
                linkedValue: nil,
                rangeMin: nil,
                nominal: nil,
                rangeMax: nil
            )
        case 2:
            guard offset + 20 <= data.count else { return nil }
            return ParsedStatValue(
                format: format,
                axisIndex: axisIndex,
                flags: flags,
                nameID: Int(OpenTypeBinary.readUInt16(data, offset + 6)),
                value: nil,
                linkedValue: nil,
                rangeMin: OpenTypeBinary.readFixed(data, offset + 12),
                nominal: OpenTypeBinary.readFixed(data, offset + 8),
                rangeMax: OpenTypeBinary.readFixed(data, offset + 16)
            )
        case 3:
            guard offset + 16 <= data.count else { return nil }
            return ParsedStatValue(
                format: format,
                axisIndex: axisIndex,
                flags: flags,
                nameID: Int(OpenTypeBinary.readUInt16(data, offset + 6)),
                value: OpenTypeBinary.readFixed(data, offset + 8),
                linkedValue: OpenTypeBinary.readFixed(data, offset + 12),
                rangeMin: nil,
                nominal: nil,
                rangeMax: nil
            )
        default:
            return nil
        }
    }
}
