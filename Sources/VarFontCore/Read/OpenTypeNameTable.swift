import CoreText
import Foundation

enum OpenTypeNameTable {
    private static let nameTableTag = OpenTypeBinary.tag("name")

    static func name(id: Int, from font: CTFont) -> String? {
        guard let data = CTFontCopyTable(font, nameTableTag, []) as Data? else { return nil }
        return bestName(id: id, in: data)
    }

    static func bestName(id: Int, in data: Data) -> String? {
        let records = parseRecords(data).filter { $0.nameID == id }
        guard !records.isEmpty, data.count >= 6 else { return nil }

        let stringOffset = Int(OpenTypeBinary.readUInt16(data, 4))
        let sorted = records.sorted { preferenceScore($0) < preferenceScore($1) }
        for record in sorted {
            if let value = decode(record: record, in: data, stringOffset: stringOffset), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func uniqueNameIDs(in data: Data) -> Set<Int> {
        Set(parseRecords(data).map { Int($0.nameID) })
    }

    static func firstFreeNameID(used: Set<Int>, startingAt: Int = 256) -> Int {
        var candidate = startingAt
        while used.contains(candidate) {
            candidate += 1
        }
        return candidate
    }

    static func standardNameLabel(for id: Int) -> String? {
        switch id {
        case 0: "Unicode copyright"
        case 1: "Font Family name"
        case 2: "Font Subfamily name"
        case 3: "Unique font identifier"
        case 4: "Full font name"
        case 5: "Version string"
        case 6: "PostScript name"
        default: nil
        }
    }

    private struct NameRecord {
        var platformID: UInt16
        var encodingID: UInt16
        var languageID: UInt16
        var nameID: UInt16
        var length: UInt16
        var offset: UInt16
    }

    private static func parseRecords(_ data: Data) -> [NameRecord] {
        guard data.count >= 6 else { return [] }
        let count = Int(OpenTypeBinary.readUInt16(data, 2))
        guard count > 0 else { return [] }

        var records: [NameRecord] = []
        var pos = 6
        for _ in 0..<count {
            guard pos + 12 <= data.count else { break }
            records.append(NameRecord(
                platformID: OpenTypeBinary.readUInt16(data, pos),
                encodingID: OpenTypeBinary.readUInt16(data, pos + 2),
                languageID: OpenTypeBinary.readUInt16(data, pos + 4),
                nameID: OpenTypeBinary.readUInt16(data, pos + 6),
                length: OpenTypeBinary.readUInt16(data, pos + 8),
                offset: OpenTypeBinary.readUInt16(data, pos + 10)
            ))
            pos += 12
        }
        return records
    }

    private static func decode(record: NameRecord, in data: Data, stringOffset: Int) -> String? {
        let start = stringOffset + Int(record.offset)
        let length = Int(record.length)
        guard start >= 0, length > 0, start + length <= data.count else { return nil }
        let slice = data[start..<(start + length)]

        switch (record.platformID, record.encodingID) {
        case (3, 1), (3, 10), (0, 3):
            return decodeUTF16BE(slice)
        case (1, 0), (1, 25):
            return String(bytes: slice, encoding: .macOSRoman)
        case (3, 0):
            return String(bytes: slice, encoding: .windowsCP1252)
        default:
            return decodeUTF16BE(slice) ?? String(bytes: slice, encoding: .macOSRoman)
        }
    }

    private static func decodeUTF16BE(_ slice: Data.SubSequence) -> String? {
        guard !slice.isEmpty, slice.count.isMultiple(of: 2) else { return nil }
        return String(data: Data(slice), encoding: .utf16BigEndian)
    }

    private static func preferenceScore(_ record: NameRecord) -> Int {
        if record.platformID == 3 {
            if record.languageID == 0x0409 { return 0 }
            if record.languageID == 0 { return 1 }
            return 2
        }
        if record.platformID == 1 {
            if record.languageID == 0 { return 3 }
            return 4
        }
        return 10
    }
}
