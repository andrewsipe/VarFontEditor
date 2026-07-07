import Foundation

public enum CommitDiffBuilder {
    public static let empty = CommitDiffReport(
        statRows: [],
        instanceRows: [],
        nameIDRows: []
    )

    public static func build(
        analysis: FontAnalysis,
        font: FontDocument,
        plan: InstancePlan,
        result: CommitResult
    ) -> CommitDiffReport {
        let protectedNameIDs = Set(result.summary?.protectedNameIDs ?? [])
        return CommitDiffReport(
            statRows: buildStatRows(analysis: analysis, font: font, diff: result.diff),
            instanceRows: buildInstanceRows(analysis: analysis, plan: plan, diff: result.diff),
            nameIDRows: buildNameIDRows(
                analysis: analysis,
                diff: result.diff,
                protectedNameIDs: protectedNameIDs
            )
        )
    }

    // MARK: - STAT

    private static func buildStatRows(
        analysis: FontAnalysis,
        font: FontDocument,
        diff: CommitDiff?
    ) -> [CommitDiffStatRow] {
        let projectTags = Set(font.axes.map(\.tag))
        var beforeByKey: [String: FontAnalysis.StatValueRecord] = [:]
        for record in analysis.statValues {
            let key = statKey(tag: record.tag, record: record)
            beforeByKey[key] = record
        }

        var afterStops: [(tag: String, stop: AxisValue)] = []
        for axis in font.axes {
            for stop in axis.values {
                afterStops.append((axis.tag, stop))
            }
        }

        let plannedByKey = Dictionary(
            uniqueKeysWithValues: (diff?.statValuesPlanned ?? []).map { item in
                (statKey(tag: item.tag, planned: item), item)
            }
        )

        let plannedNameIDs = Dictionary(
            uniqueKeysWithValues: (diff?.statValuesPlanned ?? []).compactMap { item -> (String, Int)? in
                guard let nameID = item.nameID else { return nil }
                return (statKey(tag: item.tag, planned: item), nameID)
            }
        )

        var keys = Set(afterStops.map { statKey(tag: $0.tag, stop: $0.stop) })
        for (key, before) in beforeByKey where projectTags.contains(before.tag) {
            keys.insert(key)
        }

        return keys.sorted().map { key in
            let before = beforeByKey[key]
            let afterItem = afterStops.first { statKey(tag: $0.tag, stop: $0.stop) == key }
            let planned = plannedByKey[key]
            let afterName = planned?.name ?? afterItem?.stop.name
            let afterNameID = plannedNameIDs[key]
            let change = statChangeKind(
                beforeName: before?.name,
                beforeNameID: before?.nameID,
                afterName: afterName,
                afterNameID: afterNameID
            )
            let tag = afterItem?.tag ?? before?.tag ?? key.split(separator: ":").first.map(String.init) ?? ""
            let value = afterItem?.stop.value ?? before?.value ?? before?.nominal ?? 0
            return CommitDiffStatRow(
                tag: tag,
                value: value,
                beforeName: before?.name,
                afterName: afterName,
                beforeNameID: before?.nameID,
                afterNameID: afterNameID,
                afterStatFormat: planned?.statFormat ?? afterItem?.stop.statFormat,
                afterLinkedValue: planned?.linkedValue ?? afterItem?.stop.linkedValue,
                change: change
            )
        }
        .sorted { lhs, rhs in
            if lhs.tag != rhs.tag { return lhs.tag < rhs.tag }
            return lhs.value < rhs.value
        }
    }

    private static func statChangeKind(
        beforeName: String?,
        beforeNameID: Int?,
        afterName: String?,
        afterNameID: Int?
    ) -> CommitDiffChangeKind {
        guard let afterName else {
            return beforeName == nil ? .unchanged : .removed
        }
        guard let beforeName, !beforeName.isEmpty else {
            return .added
        }
        if beforeName == afterName {
            if beforeNameID != afterNameID {
                return .changed
            }
            return .unchanged
        }
        if beforeNameID == 2 || beforeName == "Regular" {
            return .changed
        }
        return .changed
    }

    // MARK: - Instances

    private static func buildInstanceRows(
        analysis: FontAnalysis,
        plan: InstancePlan,
        diff: CommitDiff?
    ) -> [CommitDiffInstanceRow] {
        let beforeByKey = Dictionary(
            uniqueKeysWithValues: analysis.instancesExisting.map { ($0.key, $0) }
        )
        let afterByKey = Dictionary(
            uniqueKeysWithValues: plan.instances.filter(\.included).map { ($0.key, $0) }
        )
        _ = diff

        var keys = Set(beforeByKey.keys)
        keys.formUnion(afterByKey.keys)

        return keys.sorted().map { key in
            let before = beforeByKey[key]
            let after = afterByKey[key]
            let change: CommitDiffChangeKind
            if before == nil {
                change = .added
            } else if after == nil {
                change = .removed
            } else if before?.composedName == after?.composedName {
                change = .unchanged
            } else {
                change = .changed
            }
            return CommitDiffInstanceRow(
                key: key,
                beforeName: before?.composedName,
                afterName: after?.composedName,
                coords: after?.coords ?? before?.coords,
                change: change
            )
        }
    }

    // MARK: - Name IDs

    private static func buildNameIDRows(
        analysis: FontAnalysis,
        diff: CommitDiff?,
        protectedNameIDs: Set<Int> = []
    ) -> [CommitDiffNameIDRow] {
        let beforeByID = Dictionary(
            uniqueKeysWithValues: analysis.nameAudit.used
                .filter { $0.id >= 256 }
                .map { ($0.id, $0) }
        )
        let afterByID = Dictionary(
            uniqueKeysWithValues: (diff?.nameRecordsPlanned ?? []).map { ($0.id, $0) }
        )

        let allIDs = Set(beforeByID.keys).union(afterByID.keys).sorted()

        return allIDs.map { id in
            let before = beforeByID[id]
            let after = afterByID[id]
            let isProtected = protectedNameIDs.contains(id)
            let afterString = after?.string ?? (isProtected ? before?.string : nil)
            let afterRole = after?.role ?? (isProtected ? "protected_ot_label" : nil)
            let change = slotChangeKind(
                beforeString: before?.string,
                afterString: afterString,
                protected: isProtected && after == nil
            )
            return CommitDiffNameIDRow(
                id: id,
                beforeDescription: before?.description,
                beforeString: before?.string,
                afterString: afterString,
                afterRole: afterRole,
                change: change
            )
        }
    }

    private static func slotChangeKind(
        beforeString: String?,
        afterString: String?,
        protected: Bool = false
    ) -> CommitDiffChangeKind {
        if protected {
            return .unchanged
        }
        let before = beforeString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let after = afterString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasBefore = before?.isEmpty == false
        let hasAfter = after?.isEmpty == false

        switch (hasBefore, hasAfter) {
        case (false, false):
            return .unchanged
        case (false, true):
            return .added
        case (true, false):
            return .removed
        case (true, true):
            return before == after ? .unchanged : .changed
        }
    }

    private static func statKey(tag: String, stop: AxisValue) -> String {
        statKey(
            tag: tag,
            value: stop.value,
            statFormat: stop.statFormat,
            rangeMin: stop.rangeMin,
            rangeMax: stop.rangeMax
        )
    }

    private static func statKey(tag: String, record: FontAnalysis.StatValueRecord) -> String {
        statKey(
            tag: tag,
            value: record.value ?? record.nominal ?? 0,
            statFormat: record.format,
            rangeMin: record.rangeMin,
            rangeMax: record.rangeMax
        )
    }

    private static func statKey(tag: String, planned: CommitDiffStatValuePlanned) -> String {
        statKey(
            tag: tag,
            value: planned.value,
            statFormat: planned.statFormat,
            rangeMin: planned.rangeMin,
            rangeMax: planned.rangeMax
        )
    }

    private static func statKey(
        tag: String,
        value: Double,
        statFormat: Int,
        rangeMin: Double?,
        rangeMax: Double?
    ) -> String {
        let formatted = formatCoord(value)
        if statFormat == 2, let rangeMin, let rangeMax {
            return "\(tag):\(formatted)@\(formatCoord(rangeMin))-\(formatCoord(rangeMax))"
        }
        return "\(tag):\(formatted)"
    }

    private static func formatCoord(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func statKey(tag: String, value: Double) -> String {
        statKey(tag: tag, value: value, statFormat: 1, rangeMin: nil, rangeMax: nil)
    }
}
