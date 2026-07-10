import Foundation

struct FvarAxis: Sendable {
    static let hiddenAxisFlag: UInt16 = 0x0001

    var tag: String
    var min: Double
    var defaultValue: Double
    var max: Double
    var flags: UInt16
    var nameID: Int

    var isHidden: Bool { flags & Self.hiddenAxisFlag != 0 }
}

struct FvarInstance: Sendable {
    var subfamilyNameID: Int
    var postscriptNameID: Int
    var coordinates: [String: Double]
}

enum FvarParser {
    static func parse(_ data: Data) -> (axes: [FvarAxis], instances: [FvarInstance])? {
        guard data.count >= 16 else { return nil }

        let offsetToData = Int(OpenTypeBinary.readUInt16(data, 4))
        let axisCount = Int(OpenTypeBinary.readUInt16(data, 8))
        let axisSize = Int(OpenTypeBinary.readUInt16(data, 10))
        let instanceCount = Int(OpenTypeBinary.readUInt16(data, 12))
        let instanceSize = Int(OpenTypeBinary.readUInt16(data, 14))
        guard axisCount > 0, axisSize >= 20, instanceSize >= 4 + axisCount * 4 else { return nil }

        var axes: [FvarAxis] = []
        var offset = offsetToData > 0 ? offsetToData : 16
        for _ in 0..<axisCount {
            guard offset + axisSize <= data.count else { return nil }
            axes.append(
                FvarAxis(
                    tag: OpenTypeBinary.readTag(data, offset),
                    min: OpenTypeBinary.readFixed(data, offset + 4),
                    defaultValue: OpenTypeBinary.readFixed(data, offset + 8),
                    max: OpenTypeBinary.readFixed(data, offset + 12),
                    flags: OpenTypeBinary.readUInt16(data, offset + 16),
                    nameID: Int(OpenTypeBinary.readUInt16(data, offset + 18))
                )
            )
            offset += axisSize
        }

        let coordinateBytes = axisCount * 4
        let hasPostScriptNameID = instanceSize >= 4 + coordinateBytes + 2

        var instances: [FvarInstance] = []
        for _ in 0..<instanceCount {
            guard offset + instanceSize <= data.count else { break }
            let subfamilyNameID = Int(OpenTypeBinary.readUInt16(data, offset))
            var coords: [String: Double] = [:]
            var coordOffset = offset + 4
            for axis in axes {
                guard coordOffset + 4 <= data.count else { break }
                coords[axis.tag] = OpenTypeBinary.readFixed(data, coordOffset)
                coordOffset += 4
            }
            let postscriptNameID: Int
            if hasPostScriptNameID, coordOffset + 2 <= offset + instanceSize {
                postscriptNameID = Int(OpenTypeBinary.readUInt16(data, coordOffset))
            } else {
                postscriptNameID = 0xFFFF
            }
            instances.append(
                FvarInstance(
                    subfamilyNameID: subfamilyNameID,
                    postscriptNameID: postscriptNameID,
                    coordinates: coords
                )
            )
            offset += instanceSize
        }

        return (axes, instances)
    }
}
