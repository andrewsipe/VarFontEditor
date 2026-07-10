import Foundation

/// Merges a master font's axis tree into sibling project files (Push to tree).
public enum AxisTreeMerge {
    public static func mergeAxesFromMaster(
        master: [AxisDefinition],
        into target: [AxisDefinition],
        syncRoles: Bool
    ) -> [AxisDefinition] {
        let targetByTag = Dictionary(uniqueKeysWithValues: target.map { ($0.tag, $0) })
        var merged: [AxisDefinition] = []
        for masterAxis in master {
            if var existing = targetByTag[masterAxis.tag] {
                existing.displayName = masterAxis.displayName
                if !existing.isDesignRecordOnly {
                    existing.values = copyStops(from: masterAxis)
                }
                if syncRoles, !existing.isDesignRecordOnly {
                    existing.role = masterAxis.role
                }
                existing.referenceMapping = masterAxis.referenceMapping
                existing.referenceMappingInferred = masterAxis.referenceMappingInferred
                existing.referenceAnchors = masterAxis.referenceAnchors
                merged.append(existing)
            } else {
                var imported = masterAxis
                imported.values = copyStops(from: masterAxis)
                merged.append(imported)
            }
        }
        for axis in target where !master.contains(where: { $0.tag == axis.tag }) {
            merged.append(axis)
        }
        return merged
    }

    private static func copyStops(from axis: AxisDefinition) -> [AxisValue] {
        axis.values.map { stop in
            var copy = stop
            copy.id = "\(axis.tag)-\(UUID().uuidString.prefix(8))"
            return copy
        }
    }
}
